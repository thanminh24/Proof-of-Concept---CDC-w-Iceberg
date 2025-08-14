# SQL Server to Lakehouse CDC

## Description
This proof of concept demonstrates change data capture (CDC) from Microsoft SQL Server into a Lakehouse stack using Kafka, Debezium, and Apache Iceberg queried through Trino. It creates a small commerce schema in SQL Server, streams inserts through Kafka Connect, and persists them as Iceberg tables that can be queried with Trino or any compatible engine.

## Prerequisites
- Docker and Docker Compose
- Java and Maven (for connector dependencies)
- Python 3 with `requests` and `pyodbc`
- Microsoft ODBC Driver 18 for SQL Server

Install the ODBC driver (Debian/Ubuntu):

```bash
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/debian/11/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
```

Refer to [Microsoft's docs](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server) for other operating systems.

## Setup
1. Clone the repository
   ```bash
   git clone <repo-url>
   cd Proof-of-Concept---CDC-w-Iceberg
   ```
2. Resolve connector dependencies
   ```bash
   ./dependencies.sh
   ```
   Downloads:
   - `io.debezium:debezium-connector-sqlserver:3.2.0.Final`
   - `org.apache.iceberg:iceberg-kafka-connect:1.9.2`
   - Runtime jars (Hadoop 3.3.6, Hive Metastore 3.1.3, Avro 1.12.0, AWS S3 FileIO) placed under `kafka/plugins/`
3. Start services and connectors
   ```bash
   ./setup.sh
   ```
   Launches Kafka with an embedded Connect worker and SQL Server, then registers source and sink connectors.
4. Verify services and connectors
   ```bash
   docker compose exec kafka-standalone /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
   curl -s localhost:8083/connectors | jq
   curl -s localhost:8083/connectors/dbz-sqlserver-source/status | jq
   curl -s localhost:8083/connectors/iceberg-sink/status | jq
   ```
   Expected output
   ```
   __consumer_offsets
   cdc.commerce_account
   cdc.commerce_product
   ["dbz-sqlserver-source","iceberg-sink"]
   { ... dbz-sqlserver-source RUNNING ... }
   { ... iceberg-sink RUNNING ... }
   ```

## Configuration

### Key files

| File | Purpose |
| --- | --- |
| `dependencies.sh` | Downloads Debezium and Iceberg connector jars |
| `setup.sh` | Starts Docker Compose and Kafka Connect |
| `kafka/config/connect-sqlserver-source.json` | Debezium source connector configuration |
| `kafka/config/connect-iceberg-sink.json` | Iceberg sink connector configuration |
| `kafka/config/connect-standalone.properties` | Kafka Connect worker properties |
| `init_for_test.py` | Creates SQL Server tables and optional Iceberg tables |
| `test_cdc.py` | Inserts random rows and verifies CDC flow |

### SQL Server source connector
`kafka/config/connect-sqlserver-source.json`:

```json
{
  "name": "dbz-sqlserver-source",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "database.hostname": "<SQLSERVER_HOST>",
    "database.port": "1433",
    "database.user": "<SQLSERVER_USER>",
    "database.password": "<SQLSERVER_PASSWORD>",
    "database.names": "<SQLSERVER_DB>",
    "topic.prefix": "cdc",
    "schema.include.list": "<SCHEMA_LIST>",
    "table.include.list": "<TABLE_LIST>",
    "heartbeat.interval.ms": "1000",
    "snapshot.mode": "initial",
    "database.encrypt": "false",
    "schema.history.internal.kafka.topic": "<SCHEMA_HISTORY_TOPIC>",
    "schema.history.internal.kafka.bootstrap.servers": "<KAFKA_BOOTSTRAP_SERVERS>"
  }
}
```

Update `database.*`, `schema.include.list`, `table.include.list`, and schema history fields for your environment.

| Field | Purpose | How to change |
| --- | --- | --- |
| `database.hostname` / `database.port` | Location of the SQL Server instance | Point to your server and port |
| `database.user` / `database.password` | Credentials with CDC privileges | Supply replication-capable login |
| `database.names` | Databases to capture | Comma-separated list of databases |
| `schema.include.list` | Schemas to stream | List schemas from which to capture changes |
| `table.include.list` | Tables to stream | Limit to specific tables if desired |
| `topic.prefix` | Prefix for Kafka topics | Change to avoid clashes with existing topics |
| `schema.history.internal.kafka.*` | Kafka topic for schema history | Set bootstrap servers and topic name |

### Iceberg sink connector
`kafka/config/connect-iceberg-sink.json`:

```json
{
  "name": "iceberg-sink",
  "config": {
    "connector.class": "org.apache.iceberg.connect.IcebergSinkConnector",
    "tasks.max": "1",
    "errors.log.enable": "true",
    "topics.regex": "cdc.commerce.*",
    "transforms": "debezium",
    "transforms.debezium.type": "org.apache.iceberg.connect.transforms.DebeziumTransform",
    "transforms.debezium.cdc.target.pattern": "cdc.sql_{table}",
    "iceberg.tables.route-field": "_cdc.target",
    "iceberg.tables.dynamic-enabled": "true",
    "iceberg.tables.auto-create-enabled": "true",
    "iceberg.tables.evolve-schema-enabled": "true",
    "iceberg.control.commit.interval-ms": "10000",
    "iceberg.control.commit.timeout-ms": "60000",
    "iceberg.catalog": "iceberg",
    "iceberg.catalog.type": "hive",
    "iceberg.catalog.uri": "<HIVE_METASTORE_URI>",
    "iceberg.catalog.io-impl": "org.apache.iceberg.aws.s3.S3FileIO",
    "iceberg.catalog.warehouse": "<S3_WAREHOUSE_PATH>",
    "iceberg.catalog.s3.endpoint": "<S3_ENDPOINT>",
    "iceberg.catalog.s3.access-key-id": "<S3_ACCESS_KEY>",
    "iceberg.catalog.s3.secret-access-key": "<S3_SECRET_KEY>",
    "iceberg.catalog.s3.path-style-access": "true",
    "iceberg.catalog.s3.region": "<S3_REGION>",
    "iceberg.catalog.s3.signer.region": "<S3_SIGNER_REGION>",
    "iceberg.table.cdc.commerce_account.id-columns": "user_id",
    "iceberg.table.cdc.commerce_product.id-columns": "product_id"
  }
}
```

Adjust `topics.regex`, `iceberg.catalog.*`, and `iceberg.table.<topic>.id-columns` to match your catalog and tables. Modify `transforms.debezium.cdc.target.pattern` if you need a different Iceberg namespace.

| Field | Purpose | How to change |
| --- | --- | --- |
| `topics.regex` | Input topics to consume | Update regex for your CDC topic names |
| `transforms.debezium.cdc.target.pattern` | Iceberg namespace and table pattern | Modify to control destination paths |
| `iceberg.catalog`, `iceberg.catalog.*` | Catalog type and connection details | Point to your catalog implementation, hive URI, and warehouse |
| `iceberg.catalog.s3.*` | S3 connection parameters | Provide endpoint, credentials, and region |
| `iceberg.table.<topic>.id-columns` | Primary key columns for each table | Update per table to support upserts |
| `iceberg.table.<topic>.schema` | Explicit schema when auto-creating tables | Adjust to match your column definitions |

### Python scripts

#### `init_for_test.py`

| Function | Purpose | How to change |
| --- | --- | --- |
| `get_conn()` | Builds the `pyodbc` connection string | Adjust driver or credentials for your server |
| `create_sqlserver_tables()` | Defines demo schema and tables | Replace with your schema DDL |
| `insert_initial_data()` | Seeds example rows | Provide seed data relevant to your domain |
| `create_iceberg_tables()` | Creates Iceberg tables via Trino | Update table definitions or disable by leaving `CREATE_ICEBERG_TABLES=0` |

#### `test_cdc.py`

| Function | Purpose | How to change |
| --- | --- | --- |
| `get_conn()` | Reusable connection helper with retries | Adjust connection string details |
| `query_sqlserver()` | Executes SQL query and returns rows | Modify queries to target your tables |
| `insert_test_rows()` | Inserts random test data | Customize for additional columns or tables |
| `main()` | Orchestrates query/insert workflow | Extend to cover more validation steps |

### Load connectors via REST
```bash
curl -X POST -H "Content-Type: application/json" \
  --data @kafka/config/connect-sqlserver-source.json \
  http://localhost:8083/connectors
curl -X POST -H "Content-Type: application/json" \
  --data @kafka/config/connect-iceberg-sink.json \
  http://localhost:8083/connectors
```

Expected output
```bash
{"name":"dbz-sqlserver-source"}
{"name":"iceberg-sink"}
```

## Usage
### Initialize demo tables and data
```bash
python init_for_test.py
```
Expected output
```bash
Created commerce tables
Inserted seed rows
```
Set `CREATE_ICEBERG_TABLES=1` to create tables via Trino if they do not yet exist.

### Insert additional test rows
```bash
python test_cdc.py
```
Expected output
```bash
Before insert: rows listed
After insert: rows listed with new entries
```
## Features
- Docker compose stack for Kafka and SQL Server
- Automated retrieval of Debezium and Iceberg connector jars
- Shell script to launch Kafka Connect with preconfigured source and sink connectors
- Python utilities to create demo tables and push test changes

## Further reading
| Resource | Relevant sections |
| --- | --- |
| [Debezium SQL Server connector](https://debezium.io/documentation/reference/stable/connectors/sqlserver.html) | Configuration fields such as `database.names`, `schema.include.list`, `table.include.list` |
| [Apache Iceberg Kafka Connect sink](https://iceberg.apache.org/docs/latest/kafka-connect/) | Routing with `transforms.debezium.cdc.target.pattern` and table options like `iceberg.table.<topic>.id-columns` |
| [Kafka Connect REST API](https://docs.confluent.io/platform/current/connect/references/restapi.html) | Endpoints to create, list, and monitor connectors |

## License
MIT License
