#!/usr/bin/env python3
# init_for_test.py (Revised)
# Creates Postgres tables, inserts initial data, and optionally creates Iceberg tables in lakehouse via Trino HTTP API if not existing.
# Assumptions: PG_SVC=kafka-postgres, PROD_TRINO_HOST/PORT from .env (override with env)
#   CREATE_ICEBERG_TABLES=1 to enable Iceberg creation (default 0)
# Requires: pip install requests

import subprocess
import sys
import os
import requests
import json
import time

PG_SVC = os.getenv("PG_SVC", "kafka-postgres")
PROD_TRINO_HOST = os.getenv("PROD_TRINO_HOST", "10.17.26.218")
PROD_TRINO_PORT = os.getenv("PROD_TRINO_PORT", "8080")
PROD_TRINO_CATALOG = os.getenv("PROD_TRINO_CATALOG", "iceberg")
PROD_TRINO_SCHEMA = os.getenv("PROD_TRINO_SCHEMA", "cdc.db")  # Updated to match auto-created path/schema
TRINO_URL = f"http://{PROD_TRINO_HOST}:{PROD_TRINO_PORT}/v1/statement"
CREATE_ICEBERG_TABLES = int(os.getenv("CREATE_ICEBERG_TABLES", "0"))

def run(command, check=True):
    try:
        ret = subprocess.run(command, shell=True, check=check, capture_output=True, text=True)
        return ret.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e.stderr}", file=sys.stderr)
        raise

def create_postgres_tables():
    create_sql = """
    CREATE SCHEMA IF NOT EXISTS commerce;
    CREATE TABLE IF NOT EXISTS commerce.account (
        user_id SERIAL PRIMARY KEY,
        email VARCHAR(255) NOT NULL
    );
    CREATE TABLE IF NOT EXISTS commerce.product (
        product_id SERIAL PRIMARY KEY,
        product_name VARCHAR(255) NOT NULL
    );
    """
    print("Creating Postgres tables...")
    cmd = f"echo \"{create_sql}\" | docker compose exec -T {PG_SVC} psql -U postgres -d postgres"
    run(cmd)

def insert_initial_data():
    initial_sql = """
    INSERT INTO commerce.account (email) VALUES ('initial_user@example.com');
    INSERT INTO commerce.product (product_name) VALUES ('Initial Product');
    """
    print("Inserting initial data into Postgres...")
    cmd = f"echo \"{initial_sql}\" | docker compose exec -T {PG_SVC} psql -U postgres -d postgres"
    run(cmd)

def execute_trino_query(sql):
    headers = {'X-Trino-User': 'user', 'Content-Type': 'application/json'}  # Add auth if needed
    response = requests.post(TRINO_URL, headers=headers, data=sql)
    if response.status_code != 200:
        raise Exception(f"Trino query failed: {response.text}")
    data = response.json()
    next_uri = data.get('nextUri')
    results = []
    while next_uri:
        response = requests.get(next_uri, headers=headers)
        data = response.json()
        results.extend(data.get('data', []))
        next_uri = data.get('nextUri')
    return results

def table_exists(table_name):
    sql = f"SHOW TABLES FROM {PROD_TRINO_CATALOG}.{PROD_TRINO_SCHEMA} LIKE '{table_name}';"
    results = execute_trino_query(sql)
    return len(results) > 0

def create_iceberg_tables():
    if CREATE_ICEBERG_TABLES == 0:
        print("Skipping Iceberg table creation (set CREATE_ICEBERG_TABLES=1 to enable). Using existing auto-created tables.")
        return
    # Create schema if not exists
    create_schema = f"CREATE SCHEMA IF NOT EXISTS {PROD_TRINO_CATALOG}.{PROD_TRINO_SCHEMA};"
    account_table = "commerce_account"  # Adjust if pattern is postgres_account
    product_table = "commerce_product"
    create_account = f"CREATE TABLE IF NOT EXISTS {PROD_TRINO_CATALOG}.{PROD_TRINO_SCHEMA}.{account_table} (user_id BIGINT, email VARCHAR) WITH (format = 'PARQUET');"
    create_product = f"CREATE TABLE IF NOT EXISTS {PROD_TRINO_CATALOG}.{PROD_TRINO_SCHEMA}.{product_table} (product_id BIGINT, product_name VARCHAR) WITH (format = 'PARQUET');"
    print("Creating Iceberg schema and tables via Trino API if not existing...")
    execute_trino_query(create_schema)
    if not table_exists(account_table):
        execute_trino_query(create_account)
    if not table_exists(product_table):
        execute_trino_query(create_product)
    print("Iceberg tables ensured.")

def main():
    create_postgres_tables()
    insert_initial_data()
    create_iceberg_tables()
    print("Initialization complete. Tables created and initial data inserted.")

if __name__ == "__main__":
    main()