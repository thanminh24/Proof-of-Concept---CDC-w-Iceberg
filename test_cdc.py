#!/usr/bin/env python3
# test_cdc.py (Revised for External Trino HTTP API)
# Flow:
#   1) Insert test rows into Postgres
# Requires: pip install requests

import subprocess
import sys
import json
import random
import os

PG_SVC = os.getenv("PG_SVC", "kafka-postgres")
PROD_TRINO_HOST = os.getenv("PROD_TRINO_HOST", "10.17.26.218")
PROD_TRINO_PORT = os.getenv("PROD_TRINO_PORT", "8080")
PROD_TRINO_CATALOG = os.getenv("PROD_TRINO_CATALOG", "iceberg")
PROD_TRINO_SCHEMA = os.getenv("PROD_TRINO_SCHEMA", "cdc")

TRINO_URL = f"http://{PROD_TRINO_HOST}:{PROD_TRINO_PORT}"

def run(command, check=True, capture=True):
    try:
        ret = subprocess.run(command, shell=True, check=check, capture_output=capture, text=True)
        return (ret.stdout + ret.stderr).strip()
    except subprocess.CalledProcessError as e:
        out = (e.stdout or "") + (e.stderr or "")
        if capture:
            print(out, file=sys.stderr)
        if check:
            raise
        return out.strip()

def query_pg(sql):
    cmd = f'docker compose exec -T {PG_SVC} psql -U postgres -d postgres -c "{sql}"'
    return run(cmd)

def insert_test_rows():
    random_email = f"test_{random.randint(100000, 999999)}@example.com"
    random_product = f"Item_{random.choice(['A','B','C'])}{random.randint(100000, 999999)}"
    insert_sql = f"""
    INSERT INTO commerce.account (email) VALUES ('{random_email}');
    INSERT INTO commerce.product (product_name) VALUES ('{random_product}');
    """
    print("Inserting test data into PostgreSQL...")
    cmd = f"echo \"{insert_sql}\" | docker compose exec -T {PG_SVC} psql -U postgres -d postgres"
    run(cmd)
    return random_email, random_product

def main():
    print("Querying Postgres (before insert)...")
    try:
        print(query_pg("SELECT * FROM commerce.account ORDER BY user_id;"))
        print(query_pg("SELECT * FROM commerce.product ORDER BY product_id;"))
    except Exception as e:
        print(f"(warn) Failed to query Postgres baseline: {e}")

    email, product = insert_test_rows()
    print("Inserted:", email, product)

    print("Querying Postgres (after insert)...")
    try:
        print(query_pg("SELECT * FROM commerce.account ORDER BY user_id;"))
        print(query_pg("SELECT * FROM commerce.product ORDER BY product_id;"))
    except Exception as e:
        print(f"(warn) Failed to query Postgres after insert: {e}")

if __name__ == "__main__":
    main()