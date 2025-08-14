# Postgres to Lakehouse CDC

## Description
This proof of concept demonstrates change data capture (CDC) from PostgreSQL into a Lakehouse stack using Kafka, Debezium, and Apache Iceberg queried through Trino. It creates a small commerce schema in Postgres, streams inserts through Kafka Connect, and persists them as Iceberg tables that can be queried with Trino or any compatible engine.

## Installation
### Prerequisites
- Docker and Docker Compose
- Java and Maven (for connector dependencies)
- Python 3 with `requests`


### Setup Guide
1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd Proof-of-Concept---CDC-w-Iceberg
   ```
   **Key files**
   - `dependencies.sh` – downloads the Debezium PostgreSQL connector and the Iceberg Kafka Connect sink along with required Hadoop, Hive Metastore, AWS, and Avro jars
   - `setup.sh` – launches Docker Compose and starts Kafka Connect in standalone mode
   - `kafka/config/connect-postgres-source.json` – Debezium source connector configuration
   - `kafka/config/connect-iceberg-sink.json` – Iceberg sink connector configuration
   - `kafka/config/connect-standalone.properties` – worker properties including plugin paths
   - `.env` – placeholder for environment variables (credentials, endpoints)
2. **Resolve connector dependencies**
   ```bash
   ./dependencies.sh
   ```
   This script pulls:
   - `io.debezium:debezium-connector-postgres:3.1.2.Final`
   - `org.apache.iceberg:iceberg-kafka-connect:1.9.2`
   - Runtime dependencies such as Hadoop 3.3.6, Hive Metastore 3.1.3, Avro 1.12.0, and AWS S3 FileIO
   All jars are placed under `kafka/plugins/` for Kafka Connect to load.
3. **Start services and connectors**
   ```bash
   ./setup.sh
   ```
   The script brings up a Kafka broker with an embedded Connect worker and a PostgreSQL database, then registers the source and sink connectors.
4. **Verify services and connectors**
   ```bash
   docker compose exec kafka-standalone /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
   curl -s localhost:8083/connectors | jq
   curl -s localhost:8083/connectors/dbz-pg-source/status | jq
   curl -s localhost:8083/connectors/iceberg-sink/status | jq
   ```
   **Expected output**
   ```bash
   __consumer_offsets
   cdc.commerce_account
   cdc.commerce_product
   ["dbz-pg-source","iceberg-sink"]
   {
     "name": "dbz-pg-source",
     "connector": {"state": "RUNNING", "worker_id": "172.21.0.2:8083"},
     "tasks": [{"id": 0, "state": "RUNNING", "worker_id": "172.21.0.2:8083"}],
     "type": "source"
   }
   {
     "name": "iceberg-sink",
     "connector": {"state": "RUNNING", "worker_id": "172.21.0.2:8083"},
     "tasks": [{"id": 0, "state": "RUNNING", "worker_id": "172.21.0.2:8083"}],
     "type": "sink"
   }
   ```

The `.env` file is only a placeholder; all configurable properties live in the two Kafka Connect JSON files under `kafka/config`.

To load them into Kafka Connect manually, post each configuration to the REST API:

```bash
curl -X POST -H "Content-Type: application/json" \
  --data @kafka/config/connect-postgres-source.json \
  http://localhost:8083/connectors
curl -X POST -H "Content-Type: application/json" \
  --data @kafka/config/connect-iceberg-sink.json \
  http://localhost:8083/connectors
```

**Expected output**

```bash
{"name":"dbz-pg-source"}
{"name":"iceberg-sink"}
```

### PostgreSQL source connector
```json
{
  "name": "dbz-pg-source",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "<POSTGRES_HOST>",
    "database.port": "5432",
    "database.user": "<POSTGRES_USER>",
    "database.password": "<POSTGRES_PASSWORD>",
    "database.dbname": "<POSTGRES_DB>",
    "topic.prefix": "cdc",
    "schema.include.list": "<SCHEMA_LIST>",
    "heartbeat.interval.ms": "1000",
    "plugin.name": "pgoutput"
  }
}
```
Key variables:

- `database.hostname` – address of the PostgreSQL instance
- `database.port` – PostgreSQL port (default `5432`)
- `database.user` / `database.password` – replication-capable credentials
- `database.dbname` – database name to capture
- `schema.include.list` – schemas to stream
- `topic.prefix` – Kafka topic prefix for emitted events

### Iceberg sink connector
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
    "transforms.debezium.cdc.target.pattern": "cdc.{table}",
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
Adjust for your environment:

- `topics.regex` – topics to sink
- `iceberg.catalog.*` – catalog and object store settings
- `iceberg.table.<topic>.id-columns` – primary key columns used for upserts

## Usage
1. **Initialize demo tables and data**
   ```bash
   python init_for_test.py
   ```
   **Expected output**
   ```bash
   Created commerce tables
   Inserted seed rows
   ```
   Set `CREATE_ICEBERG_TABLES=1` to have the script create Iceberg tables via the Trino API if they do not yet exist.

2. **Insert additional test rows**
   ```bash
   python test_cdc.py
   ```
   **Expected output**
   ```bash
   Before insert: 5 rows
   After insert: 6 rows
   ```
   The script inserts random rows into the Postgres `commerce` schema and prints their presence before and after the insert.

Environment variables such as `PG_SVC`, `PROD_TRINO_HOST`, `PROD_TRINO_PORT`, `PROD_TRINO_CATALOG`, and `PROD_TRINO_SCHEMA` allow overriding defaults for both scripts.

## Features
- Docker compose stack for Kafka and PostgreSQL
- Automated retrieval of Debezium and Iceberg connector jars
- Shell script to launch Kafka Connect with preconfigured source and sink connectors
- Python utilities to create demo tables and push test changes

## Further reading

### Debezium PostgreSQL connector

Key configuration fields:

| Field | Purpose |
| --- | --- |
| `database.hostname` | Host of the source PostgreSQL database |
| `database.port` | Port that PostgreSQL listens on |
| `database.user` | User with replication privileges |
| `topic.prefix` | Prefix applied to Kafka topics |
| `schema.include.list` | Schemas to capture changes from |

Reference: [Debezium PostgreSQL connector documentation](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)

### Apache Iceberg Kafka Connect sink

Key configuration fields:

| Field | Purpose |
| --- | --- |
| `topics.regex` | Regex selecting input topics |
| `iceberg.catalog` | Catalog name registered in Kafka Connect |
| `iceberg.catalog.uri` | Hive metastore Thrift URI |
| `iceberg.catalog.warehouse` | Warehouse path for table storage |
| `iceberg.table.<table>.id-columns` | Primary key columns for each table |

Reference: [Apache Iceberg Kafka Connect sink documentation](https://iceberg.apache.org/docs/latest/kafka-connect/)

### Kafka Connect REST API

Useful endpoints:

| Endpoint | Purpose |
| --- | --- |
| `GET /connectors` | List available connectors |
| `GET /connectors/{name}` | Retrieve configuration and status |
| `POST /connectors` | Create a new connector |
| `DELETE /connectors/{name}` | Remove a connector |

Reference: [Kafka Connect REST API documentation](https://docs.confluent.io/platform/current/connect/references/restapi.html)

## License
MIT License
