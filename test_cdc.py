#!/usr/bin/env python3
# test_cdc.py (Revised for SQL Server via pyodbc)
# Flow:
#   1) Insert test rows into SQL Server
# Requires: pip install requests pyodbc

import pyodbc
import sys
import json
import random
import os

PROD_TRINO_HOST = os.getenv("PROD_TRINO_HOST", "10.17.26.218")
PROD_TRINO_PORT = os.getenv("PROD_TRINO_PORT", "8080")
PROD_TRINO_CATALOG = os.getenv("PROD_TRINO_CATALOG", "iceberg")
PROD_TRINO_SCHEMA = os.getenv("PROD_TRINO_SCHEMA", "cdc")

SQLSERVER_HOST = os.getenv("SQLSERVER_HOST", "kafka-sqlserver")
SQLSERVER_PORT = os.getenv("SQLSERVER_PORT", "1433")
SQLSERVER_USER = os.getenv("SQLSERVER_USER", "sa")
SQLSERVER_PASSWORD = os.getenv("SQLSERVER_PASSWORD", "YourStrongPassword123!")
SQLSERVER_DB = os.getenv("SQLSERVER_DB", "postgres")

TRINO_URL = f"http://{PROD_TRINO_HOST}:{PROD_TRINO_PORT}"

def get_conn():
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={SQLSERVER_HOST},{SQLSERVER_PORT};"
        f"DATABASE={SQLSERVER_DB};"
        f"UID={SQLSERVER_USER};"
        f"PWD={SQLSERVER_PASSWORD}"
    )
    return pyodbc.connect(conn_str)

def query_sqlserver(sql):
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql)
        rows = cur.fetchall()
        return "\n".join(str(row) for row in rows)

def insert_test_rows():
    random_email = f"test_{random.randint(100000, 999999)}@example.com"
    random_product = f"Item_{random.choice(['A','B','C'])}{random.randint(100000, 999999)}"
    insert_sql = f"""
    INSERT INTO commerce.account (email) VALUES ('{random_email}');
    INSERT INTO commerce.product (product_name) VALUES ('{random_product}');
    """
    print("Inserting test data into SQL Server...")
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(insert_sql)
        conn.commit()
    return random_email, random_product

def main():
    print("Querying SQL Server (before insert)...")
    try:
        print(query_sqlserver("SELECT * FROM commerce.account ORDER BY user_id;"))
        print(query_sqlserver("SELECT * FROM commerce.product ORDER BY product_id;"))
    except Exception as e:
        print(f"(warn) Failed to query SQL Server baseline: {e}")

    email, product = insert_test_rows()
    print("Inserted:", email, product)

    print("Querying SQL Server (after insert)...")
    try:
        print(query_sqlserver("SELECT * FROM commerce.account ORDER BY user_id;"))
        print(query_sqlserver("SELECT * FROM commerce.product ORDER BY product_id;"))
    except Exception as e:
        print(f"(warn) Failed to query SQL Server after insert: {e}")

if __name__ == "__main__":
    main()
