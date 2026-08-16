# SQL Data Warehouse

A modern data warehouse built with SQL Server, consolidating sales data from two source systems
(ERP and CRM) into a clean, integrated star schema ready for analytical reporting.

Built on the **medallion architecture** — bronze, silver, gold — with **Kimball dimensional
modeling** in the gold layer.

---

## Architecture

```
Sources                Data Warehouse                        Consume
─────────    ──────────────────────────────────────    ──────────────────
 CRM  ─┐     ┌────────┐   ┌────────┐   ┌────────┐       BI & Reporting
       ├─EL─▶│ Bronze │──▶│ Silver │──▶│  Gold  │──▶    Ad-hoc SQL
 ERP  ─┘     │  raw   │ETL│ clean  │ TL│business│       Machine Learning
             │ tables │   │ tables │   │ views  │
             └────────┘   └────────┘   └────────┘
```

| Layer | Contents | Object type | Load | Audience |
|---|---|---|---|---|
| **Bronze** | Raw, unprocessed data as-is from source | Tables | Full load — truncate & insert | Data engineers |
| **Silver** | Cleaned, standardized, typed | Tables | Full load — truncate & insert | Analysts, engineers |
| **Gold** | Business-ready star schema | Views | None (computed on read) | Analysts, business users |

Full design rationale in [`docs/data_architecture.md`](docs/data_architecture.md).

## Source systems

| Source | Files | Rows |
|---|---|---|
| CRM | `cust_info`, `prd_info`, `sales_details` | 18,494 · 397 · 60,398 |
| ERP | `CUST_AZ12`, `LOC_A101`, `PX_CAT_G1V2` | 18,484 · 18,484 · 37 |

The two systems share no key format — customer IDs need prefix stripping and separator removal to
reconcile, and the CRM product key is a composite carrying two different foreign keys. Full profiling,
including every measured data-quality defect, in
[`docs/source_systems_analysis.md`](docs/source_systems_analysis.md).

## Project scope

- **Data quality** — cleanse and resolve issues before analysis
- **Integration** — combine both sources into one user-friendly model
- **Scope** — latest dataset only; historization is *not* required (SCD 1, full reload)
- **Documentation** — model documented for business stakeholders and analytics teams

## Repository structure

```
datasets/          source CSVs (source_crm/, source_erp/)
scripts/
  init_database.sql        create database + bronze/silver/gold schemas
  bronze/                  DDL + load procedure
  silver/                  DDL + load procedure
  gold/                    star-schema view definitions
tests/                     data-quality checks per layer
docs/                      architecture, naming conventions, source analysis, data catalog
```

## Getting started

Requires Docker. SQL Server 2022 runs in a container; on Apple Silicon it runs under Rosetta
emulation, since there is no arm64 build.

```bash
# set your SA password
cp .env.example .env && edit .env      # then:
export $(grep -v '^#' .env | xargs)

# start SQL Server
docker run -d --name sqlserver --platform linux/amd64 \
  -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
  -e MSSQL_PID=Developer -e MSSQL_MEMORY_LIMIT_MB=3072 \
  -p 1433:1433 -v "$PWD":/project \
  mcr.microsoft.com/mssql/server:2022-latest

# create the database and schemas
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b \
  -i /project/scripts/init_database.sql
```

Connect a GUI client (Azure Data Studio, DBeaver, or the VS Code `mssql` extension) to
`localhost,1433` as `sa`.

> `BULK INSERT` executes inside the container and cannot see the host filesystem — all data paths
> in the load scripts use the `/project/...` mount, not host paths.

## Documentation

| Document | Contents |
|---|---|
| [`data_architecture.md`](docs/data_architecture.md) | Layer design, architecture rules, ETL profile, why medallion over Inmon/Data Vault |
| [`naming_conventions.md`](docs/naming_conventions.md) | Naming rules for databases, schemas, tables, columns, procedures |
| [`source_systems_analysis.md`](docs/source_systems_analysis.md) | Source profiling, join-key bridges, measured data-quality defects |

## License

MIT — see [LICENSE](LICENSE).
