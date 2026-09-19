// RoaDo Data Analyst Intern Assignment
// MongoDB Aggregation Pipelines
// ------------------------------------------------------------------

// Note: The raw MongoDB event logs have really messy schema structures.
// We handle ID normalization (customerId vs customer_id) directly inside the pipelines using $ifNull and $addFields.


// ------------------------------------------------------------------
// Q1: Weekly session counts and duration percentiles per tier
// 
// Note: In production, the 'userTiers' array below would be injected dynamically from our PostgreSQL database.
var userTiers = [
    { member_id: 1, tier: 'Free' },
    { member_id: 2, tier: 'Enterprise' }
    // ... imported from PostgreSQL
];

db.user_activity_logs.aggregate([
    // First, clean up the messy IDs and timestamps
    {
        $addFields: {
            normalized_member_id: { $ifNull: ["$member_id", { $ifNull: ["$memberId", "$userId"] }] },
            normalized_date: { $toDate: "$timestamp" }
        }
    },
    // Keep only valid completed sessions
    { $match: { event_type: "session_end", session_duration_sec: { $gt: 0 } } },
    
    // Group by user and week to get the raw weekly counts
    {
        $group: {
            _id: {
                member_id: "$normalized_member_id",
                year: { $year: "$normalized_date" },
                week: { $isoWeek: "$normalized_date" }
            },
            weekly_sessions: { $sum: 1 },
            durations: { $push: "$session_duration_sec" }
        }
    },
    // Roll up to the user level to find their average weekly cadence
    {
        $group: {
            _id: "$_id.member_id",
            avg_weekly_sessions: { $avg: "$weekly_sessions" },
            all_durations: { $push: "$durations" }
        }
    },
    // Roll up to the Plan Tier level (requires SQL injection logic)
    {
        $group: {
            _id: "$tier", 
            avg_sessions_per_user_per_week: { $avg: "$avg_weekly_sessions" },
            durations: { $push: "$all_durations" } 
        }
    },
    {
        $project: {
            tier: "$_id",
            avg_sessions_per_user_per_week: 1,
            // Assuming MongoDB 7.0+ for native percentiles. Otherwise, we'd pull this into Python.
            session_duration_percentiles: {
                $percentile: {
                    input: "$durations",
                    p: [0.25, 0.5, 0.75],
                    method: "approximate"
                }
            }
        }
    }
]);


// ------------------------------------------------------------------
// Q2: Feature DAU and 7-day retention
// Calculates how many users came back to use a specific feature within 7 days of their first use.
db.user_activity_logs.aggregate([
    {
        $addFields: {
            normalized_member_id: { $ifNull: ["$member_id", { $ifNull: ["$memberId", "$userId"] }] },
            date_only: { $dateTrunc: { date: { $toDate: "$timestamp" }, unit: "day" } }
        }
    },
    { $match: { feature: { $exists: true, $ne: null } } },
    
    // Sort chronologically so the first record is guaranteed to be their true "first use"
    { $sort: { "normalized_member_id": 1, "feature": 1, "date_only": 1 } },
    
    // Build a history of usage dates for each user/feature combo
    {
        $group: {
            _id: {
                member_id: "$normalized_member_id",
                feature: "$feature"
            },
            first_used_date: { $first: "$date_only" },
            all_usage_dates: { $addToSet: "$date_only" }
        }
    },
    // Check if any date in their history falls within the 7-day window after their first use
    {
        $addFields: {
            returned_within_7d: {
                $gt: [
                    {
                        $size: {
                            $filter: {
                                input: "$all_usage_dates",
                                as: "usage_date",
                                cond: {
                                    $and: [
                                        { $gt: ["$$usage_date", "$first_used_date"] },
                                        { $lte: ["$$usage_date", { $dateAdd: { startDate: "$first_used_date", unit: "day", amount: 7 } }] }
                                    ]
                                }
                            }
                        }
                    },
                    0
                ]
            }
        }
    },
    // Roll up to the feature level to calculate the final retention rate
    {
        $group: {
            _id: "$_id.feature",
            total_users: { $sum: 1 },
            retained_users: { $sum: { $cond: ["$returned_within_7d", 1, 0] } }
        }
    },
    {
        $project: {
            feature: "$_id",
            total_users: 1,
            retention_rate_7d: { $divide: ["$retained_users", "$total_users"] }
        }
    }
]);


// ------------------------------------------------------------------
// Q3: Onboarding Funnel Analysis
// Tracks drop-off rates and time-to-convert across the 5 core onboarding steps.
db.onboarding_events.aggregate([
    {
        $addFields: {
            normalized_member_id: { $ifNull: ["$member_id", { $ifNull: ["$memberId", "$userId"] }] },
            normalized_date: { $toDate: "$timestamp" }
        }
    },
    {
        $group: {
            _id: "$normalized_member_id",
            signup_time: { $min: { $cond: [{ $eq: ["$event_type", "signup"] }, "$normalized_date", null] } },
            first_login_time: { $min: { $cond: [{ $eq: ["$event_type", "first_login"] }, "$normalized_date", null] } },
            workspace_time: { $min: { $cond: [{ $eq: ["$event_type", "workspace_created"] }, "$normalized_date", null] } },
            project_time: { $min: { $cond: [{ $eq: ["$event_type", "first_project"] }, "$normalized_date", null] } },
            invite_time: { $min: { $cond: [{ $eq: ["$event_type", "invited_teammate"] }, "$normalized_date", null] } }
        }
    },
    // Flag whether the user successfully reached each stage, and how long it took them
    {
        $project: {
            reached_signup: { $cond: [{ $ne: ["$signup_time", null] }, 1, 0] },
            reached_login: { $cond: [{ $and: [{ $ne: ["$signup_time", null] }, { $ne: ["$first_login_time", null] }] }, 1, 0] },
            reached_workspace: { $cond: [{ $and: [{ $ne: ["$first_login_time", null] }, { $ne: ["$workspace_time", null] }] }, 1, 0] },
            reached_project: { $cond: [{ $and: [{ $ne: ["$workspace_time", null] }, { $ne: ["$project_time", null] }] }, 1, 0] },
            reached_invite: { $cond: [{ $and: [{ $ne: ["$project_time", null] }, { $ne: ["$invite_time", null] }] }, 1, 0] },
            
            time_to_login: { $subtract: ["$first_login_time", "$signup_time"] },
            time_to_workspace: { $subtract: ["$workspace_time", "$first_login_time"] },
            time_to_project: { $subtract: ["$project_time", "$workspace_time"] },
            time_to_invite: { $subtract: ["$invite_time", "$project_time"] }
        }
    },
    // Final funnel summary metrics
    {
        $group: {
            _id: null,
            total_signup: { $sum: "$reached_signup" },
            total_login: { $sum: "$reached_login" },
            total_workspace: { $sum: "$reached_workspace" },
            total_project: { $sum: "$reached_project" },
            total_invite: { $sum: "$reached_invite" },
            avg_time_to_login: { $avg: "$time_to_login" },
            avg_time_to_workspace: { $avg: "$time_to_workspace" },
            avg_time_to_project: { $avg: "$time_to_project" },
            avg_time_to_invite: { $avg: "$time_to_invite" }
        }
    }
]);


// ------------------------------------------------------------------
// Q4: Identify Free-Tier Upsell Targets
// We calculate an engagement score based on habitual use and feature discovery.

// The list of free_tier_customers would be injected from our SQL database.
var free_tier_customers = [ 101, 102, 205 ];

db.user_activity_logs.aggregate([
    {
        $addFields: {
            normalized_customer_id: { 
                $toInt: { $ifNull: ["$customer_id", { $ifNull: ["$customerId", "$customerID"] }] } 
            }
        }
    },
    // Filter down to only Free Tier customers based on the SQL list
    { $match: { normalized_customer_id: { $in: free_tier_customers } } },
    
    // Compile the 3 core metrics we need for our engagement score
    {
        $group: {
            _id: "$normalized_customer_id",
            active_days: { $addToSet: { $dateTrunc: { date: { $toDate: "$timestamp" }, unit: "day" } } },
            total_sessions: { $sum: { $cond: [{ $eq: ["$event_type", "session_end"] }, 1, 0] } },
            distinct_features: { $addToSet: "$feature" }
        }
    },
    {
        $project: {
            customer_id: "$_id",
            active_days_count: { $size: "$active_days" },
            total_sessions: 1,
            distinct_features_count: { $size: "$distinct_features" },
            
            // Composite Engagement Score: (Days * 2) + (Sessions * 1) + (Features * 5)
            // Justification: Logging in multiple days proves habitual use. Exploring multiple features proves depth of product knowledge.
            // Both are much stronger signals for an upsell than raw session volume.
            engagement_score: {
                $add: [
                    { $multiply: [{ $size: "$active_days" }, 2] },
                    { $multiply: ["$total_sessions", 1] },
                    { $multiply: [{ $size: "$distinct_features" }, 5] }
                ]
            }
        }
    },
    // Grab the top 20 most engaged users for the Sales team
    { $sort: { engagement_score: -1 } },
    { $limit: 20 }
]);
