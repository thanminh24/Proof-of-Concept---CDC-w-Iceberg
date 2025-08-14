# test_cdc.py (Revised for SQL Server via pyodbc)
# Flow:
#   1) Query SQL Server tables
#   2) Insert test rows into SQL Server
#   3) Re-query to verify inserts
# Requires: pip install pyodbc

import pyodbc
import os
import random
import time
from typing import Tuple

# Configuration from environment variables
SQLSERVER_HOST = os.getenv("SQLSERVER_HOST", "localhost")
SQLSERVER_PORT = os.getenv("SQLSERVER_PORT", "1433")
SQLSERVER_USER = os.getenv("SQLSERVER_USER", "sa")
SQLSERVER_PASSWORD = os.getenv("SQLSERVER_PASSWORD", "YourStrongPassword123!")
SQLSERVER_DB = os.getenv("SQLSERVER_DB", "commerce")

def get_conn(max_retries: int = 10, retry_delay: int = 5) -> pyodbc.Connection:
    """Establish a connection to SQL Server with retries."""
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SQLSERVER_HOST},{SQLSERVER_PORT};"
        f"DATABASE={SQLSERVER_DB};"
        f"UID={SQLSERVER_USER};"
        f"PWD={SQLSERVER_PASSWORD};"
        "TrustServerCertificate=Yes"
    )
    for attempt in range(max_retries):
        try:
            print(f"Attempting to connect to SQL Server at {SQLSERVER_HOST}:{SQLSERVER_PORT}...")
            conn = pyodbc.connect(conn_str)
            print(f"Connected to SQL Server at {SQLSERVER_HOST}")
            return conn
        except pyodbc.Error as e:
            print(f"Connection attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise Exception(f"Failed to connect to SQL Server after {max_retries} attempts: {e}")

def query_sqlserver(sql: str) -> str:
    """Execute a SQL query and return results as a string."""
    try:
        with get_conn() as conn:
            cur = conn.cursor()
            cur.execute(sql)
            rows = cur.fetchall()
            return "\n".join(str(row) for row in rows)
    except pyodbc.Error as e:
        return f"Query failed: {e}"

def insert_test_rows() -> Tuple[str, str]:
    """Insert random test data into account and product tables."""
    random_email = f"test_{random.randint(100000, 999999)}@example.com"
    random_product = f"Item_{random.choice(['A', 'B', 'C'])}{random.randint(100000, 999999)}"
    insert_sql = """
    INSERT INTO commerce.account (email) VALUES (?);
    INSERT INTO commerce.product (product_name) VALUES (?);
    """
    print("Inserting test data into SQL Server...")
    try:
        with get_conn() as conn:
            cur = conn.cursor()
            cur.execute(insert_sql, (random_email, random_product))
            conn.commit()
        print(f"Inserted: {random_email}, {random_product}")
        return random_email, random_product
    except pyodbc.Error as e:
        print(f"Insert failed: {e}")
        return "", ""

def main():
    """Main function to query, insert, and re-query SQL Server tables."""
    # Query before insert
    print("Querying SQL Server (before insert)...")
    print("Accounts:")
    print(query_sqlserver("SELECT * FROM commerce.account ORDER BY user_id;"))
    print("Products:")
    print(query_sqlserver("SELECT * FROM commerce.product ORDER BY product_id;"))

    # Insert test data
    email, product = insert_test_rows()

    # Query after insert
    print("\nQuerying SQL Server (after insert)...")
    print("Accounts:")
    print(query_sqlserver("SELECT * FROM commerce.account ORDER BY user_id;"))
    print("Products:")
    print(query_sqlserver("SELECT * FROM commerce.product ORDER BY product_id;"))

if __name__ == "__main__":
    main()