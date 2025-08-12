#!/usr/bin/env python3
# init_for_test.py (Revised for SQL Server)
# Creates SQL Server tables, inserts initial data, and optionally creates Iceberg tables in lakehouse via Trino HTTP API if not existing.
# Assumptions: SQL Server service accessible via env vars, PROD_TRINO_* from .env
#   CREATE_ICEBERG_TABLES=1 to enable Iceberg creation (default 0)
# Requires: pip install requests pyodbc

import pyodbc
import sys
import os
import requests

SQLSERVER_HOST = os.getenv("SQLSERVER_HOST", "kafka-sqlserver")
SQLSERVER_PORT = os.getenv("SQLSERVER_PORT", "1433")
SQLSERVER_USER = os.getenv("SQLSERVER_USER", "sa")
SQLSERVER_PASSWORD = os.getenv("SQLSERVER_PASSWORD", "YourStrongPassword123!")
SQLSERVER_DB = os.getenv("SQLSERVER_DB", "postgres")

PROD_TRINO_HOST = os.getenv("PROD_TRINO_HOST", "10.17.26.218")
PROD_TRINO_PORT = os.getenv("PROD_TRINO_PORT", "8080")
PROD_TRINO_CATALOG = os.getenv("PROD_TRINO_CATALOG", "iceberg")
PROD_TRINO_SCHEMA = os.getenv("PROD_TRINO_SCHEMA", "cdc")  # Updated to match auto-created path/schema
TRINO_URL = f"http://{PROD_TRINO_HOST}:{PROD_TRINO_PORT}/v1/statement"
CREATE_ICEBERG_TABLES = int(os.getenv("CREATE_ICEBERG_TABLES", "0"))

def get_conn():
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={SQLSERVER_HOST},{SQLSERVER_PORT};"
        f"DATABASE={SQLSERVER_DB};"
        f"UID={SQLSERVER_USER};"
        f"PWD={SQLSERVER_PASSWORD}"
    )
    return pyodbc.connect(conn_str)

def create_sqlserver_tables():
    create_sql = """
    CREATE SCHEMA IF NOT EXISTS commerce;
    CREATE TABLE IF NOT EXISTS commerce.account (
        user_id INT IDENTITY(1,1) PRIMARY KEY,
        email VARCHAR(255) NOT NULL
    );
    CREATE TABLE IF NOT EXISTS commerce.product (
        product_id INT IDENTITY(1,1) PRIMARY KEY,
        product_name VARCHAR(255) NOT NULL
    );
    """
    print("Creating SQL Server tables...")
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(create_sql)
        conn.commit()

def insert_initial_data():
    initial_sql = """
    INSERT INTO commerce.account (email) VALUES ('initial_user@example.com');
    INSERT INTO commerce.product (product_name) VALUES ('Initial Product');
    """
    print("Inserting initial data into SQL Server...")
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(initial_sql)
        conn.commit()

def execute_trino_query(sql):
    headers = {'X-Trino-User': 'user', 'Content-Type': 'application/json'}
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
    create_schema = f"CREATE SCHEMA IF NOT EXISTS {PROD_TRINO_CATALOG}.{PROD_TRINO_SCHEMA};"
    account_table = "commerce_account"
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
    create_sqlserver_tables()
    insert_initial_data()
    create_iceberg_tables()
    print("Initialization complete. Tables created and initial data inserted.")

if __name__ == "__main__":
    main()

