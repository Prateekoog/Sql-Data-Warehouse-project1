# SQL Data Warehouse

A modern data warehouse built with PostgreSQL, consolidating sales data from two source systems
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
  bronze/                  DDL + load script (\copy)
  silver/                  DDL + transformation script
  gold/                    star-schema view definitions
tests/                     data-quality checks per layer
docs/                      architecture, naming conventions, source analysis, data catalog
```

## Getting started

Requires PostgreSQL 13+ and `psql`. Run every command **from the repo root** — the bronze load
uses `\copy` with paths relative to where `psql` is started.

```bash
psql -d postgres      -f scripts/init_database.sql          # create database + schemas (drops it if it exists)
psql -d datawarehouse -f scripts/bronze/ddl_bronze.sql
psql -d datawarehouse -f scripts/bronze/proc_load_bronze.sql  # load the six CSVs
psql -d datawarehouse -f tests/quality_checks_bronze.sql      # every check should print PASS
psql -d datawarehouse -f scripts/silver/ddl_silver.sql
psql -d datawarehouse -f scripts/silver/proc_load_silver.sql
psql -d datawarehouse -f scripts/gold/ddl_gold.sql             # star-schema views
```

> Use `psql`, not pgAdmin's Query Tool, for these scripts: `\c` and `\copy` are psql commands.
> After the load, any client (pgAdmin, DBeaver) can query the `gold` views.

Tested end to end on PostgreSQL 16: all bronze quality checks pass, and `gold.fact_sales` holds
60,398 rows with no orphan customer or product keys.

## Documentation

| Document | Contents |
|---|---|
| [`data_architecture.md`](docs/data_architecture.md) | Layer design, architecture rules, ETL profile, why medallion over Inmon/Data Vault |
| [`naming_conventions.md`](docs/naming_conventions.md) | Naming rules for databases, schemas, tables, columns, procedures |
| [`source_systems_analysis.md`](docs/source_systems_analysis.md) | Source profiling, join-key bridges, measured data-quality defects |

## License

MIT — see [LICENSE](LICENSE).
