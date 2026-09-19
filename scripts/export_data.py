import os
import pandas as pd
from sqlalchemy import create_engine
from pymongo import MongoClient

# Setup output directory
output_dir = r"D:\.workspace\assignment\RoaDo_Data_Analyst_Assignment\output\raw"
os.makedirs(output_dir, exist_ok=True)

print("Connecting to PostgreSQL...")
# PostgreSQL connection (using the local credentials we know)
engine = create_engine('postgresql+psycopg2://postgres:ce8984d2bc454390a1bb22652db8a8d5@localhost:5432/postgres')

# Export SQL Tables
sql_tables = {
    "customers.csv": "SELECT * FROM nimbus.customers",
    "subscriptions.csv": "SELECT * FROM nimbus.subscriptions",
    "support_tickets.csv": "SELECT * FROM nimbus.support_tickets",
    "plans.csv": "SELECT * FROM nimbus.plans"
}

for filename, query in sql_tables.items():
    print(f"Exporting {filename} from PostgreSQL...")
    df = pd.read_sql(query, engine)
    df.to_csv(os.path.join(output_dir, filename), index=False)


print("Connecting to MongoDB...")
# MongoDB connection
client = MongoClient('mongodb://127.0.0.1:27017/?directConnection=true')
db = client['nimbus_events']

# Export Mongo Collections
mongo_collections = {
    "activity_clean.csv": db.user_activity_logs,
    "nps.csv": db.nps_survey_responses,
    "onboarding.csv": db.onboarding_events
}

for filename, collection in mongo_collections.items():
    print(f"Exporting {filename} from MongoDB...")
    # Fetch all records
    cursor = collection.find({})
    df = pd.DataFrame(list(cursor))
    
    # Drop the MongoDB specific _id column if it exists to clean up the CSV
    if '_id' in df.columns:
        df.drop(columns=['_id'], inplace=True)
        
    df.to_csv(os.path.join(output_dir, filename), index=False)

print("Step 8 Export Complete!")
