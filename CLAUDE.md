# SQL Data Warehouse

A portfolio data-warehouse build: consolidate sales data from two source systems (ERP + CRM,
delivered as CSVs) into a clean, integrated, query-friendly dimensional model.

## Project brief

| Spec | Requirement |
|---|---|
| **Objective** | Modern data warehouse consolidating sales data for analytical reporting and decision-making |
| **Sources** | Two systems — ERP and CRM — provided as CSV files |
| **Data quality** | Cleanse and resolve quality issues *before* analysis |
| **Integration** | Combine both sources into one user-friendly model designed for analytical queries |
| **Scope** | **Latest dataset only — historization is NOT required** |
| **Documentation** | Document the data model for business stakeholders *and* analytics teams |

### What "no historization" rules out

This is the single most load-bearing constraint. It means:

- **SCD 1 / SCD 0 only.** Overwrite on change. No `valid_from` / `valid_to` / `is_current` columns.
- **Full load, truncate & insert.** Every pipeline run wipes the target tables and reloads from
  scratch. No incremental extraction, no CDC, no merge/upsert logic, no watermark tracking.
- **Surrogate keys are generated at load time** (`ROW_NUMBER()`), not persisted across runs.
  Safe precisely because a business entity is always exactly one row.

Do not add historization "just in case" — it is explicitly out of scope.

## Architecture — medallion (bronze → silver → gold)

```
CSV sources ──EL──▶ bronze ──ETL──▶ silver ──TL──▶ gold ──T──▶ (views)
```

| | **Bronze** | **Silver** | **Gold** |
|---|---|---|---|
| **Definition** | Raw, unprocessed data as-is from sources | Clean & standardized data | Business-ready data |
| **Objective** | Traceability & debugging | Intermediate layer — prepare data for analysis | Provide data to be consumed for reporting & analytics |
| **Object type** | Tables | Tables | **Views** |
| **Load method** | Full load (truncate & insert) | Full load (truncate & insert) | None — computed on read |
| **Transformations** | **None (as-is)** | Cleaning, standardization, normalization, derived columns, enrichment | Integration, aggregation, business logic & rules |
| **Data modeling** | **None (as-is)** | **None (as-is)** | Star schema, aggregated objects, flat tables |
| **Audience** | Data engineers | Data analysts, data engineers | Data analysts, business users |

Rules:
- Each layer reads **only** from the layer immediately below it. Never skip a layer.
- Bronze is never transformed. If you're tempted to clean something in bronze, it belongs in silver.
- Gold is views, not tables — no persistence layer to keep in sync.

## Data model target

Star schema is the primary gold model — facts narrow and tall, dimensions flat and wide, no
snowflaking, denormalize deliberately. Gold may additionally expose aggregated objects and flat
wide tables where a consumer needs them; the star schema stays the backbone.

- **Grain must be stated explicitly** for every fact table, in a comment at the top of its definition,
  and never mixed. This is the first thing to decide when adding a fact.
- Every dimension carries both a **surrogate key** (`*_key`, meaningless integer, the join key) and
  the **source business key** (`*_id`, traceability back to the source system).

## Naming conventions

Full rules in `docs/naming_conventions.md`. Summary:

- `snake_case` throughout, lowercase, English. No spaces, no reserved words.
- **bronze / silver**: `<source_system>_<entity>` — e.g. `crm_cust_info`, `erp_loc_a101`.
  Keep the source's exact table name; never beautify it. Renaming happens once, at the gold boundary.
- **gold**: `<category>_<entity>` — `dim_customers`, `fact_sales`, `agg_*`, `report_*`.
- Surrogate keys: `<entity>_key`. Business keys: `<entity>_id`.
- Technical/metadata columns: `dwh_` prefix (e.g. `dwh_create_date`).
- Stored procedures: `load_<layer>` (e.g. `load_bronze`, `load_silver`).

## Conventions for SQL in this repo

- Every script is **idempotent and re-runnable** — no manual cleanup between runs.
- Loading procedures print progress and per-step duration, and wrap the body in error handling.
- Comment the *why* (the data-quality issue being fixed), not the *what*. Cleansing logic is
  meaningless without the defect it addresses.
- Quality checks are their own scripts, run after each layer loads — not folded into the load.

## Repository layout

```
datasets/          source CSVs (source_crm/, source_erp/)
scripts/
  init_database.sql        create database + bronze/silver/gold schemas
  bronze/                  DDL + load procedure
  silver/                  DDL + load procedure
  gold/                    star-schema view definitions
tests/                     data-quality checks per layer
docs/                      data catalog, model diagrams, data flow
```

## Open decisions

These are **not yet settled** — ask before assuming:

1. **Source CSVs.** The ERP/CRM datasets are not in `datasets/` yet.
2. **Analytics layer.** Whether the build stops at gold or continues into a reporting/analytics
   query set on top.

## Engine — SQL Server 2022 in Docker

**Decided.** Write standard T-SQL (`GO` batches, `NVARCHAR`, `IDENTITY`, `BULK INSERT`, `ISNULL`,
`GETDATE()`) — no Postgres translation.

Host is Apple Silicon (arm64) with 8GB RAM. There is no arm64 build of SQL Server, so the amd64
image runs under Rosetta inside the Colima VM.

- Runtime: Colima (`vmType: vz`, Rosetta enabled), 4 CPU / 5GB — raised from 2 CPU / 2GB, which was
  below SQL Server's 2GB minimum.
- Image: `mcr.microsoft.com/mssql/server:2022-latest`, run with `--platform linux/amd64`.
- Client: `sqlcmd` is not installed on the host — run it inside the container via `docker exec`
  (`/opt/mssql-tools18/bin/sqlcmd`, needs `-C` to trust the self-signed cert).
- Memory is the binding constraint on this machine. Expect the container to be the heaviest process
  running; `colima stop` when not working on this project.

### Runbook

Connection: `localhost,1433` · user `sa` · Developer edition, 3072 MB cap.
Password lives in `.env` (gitignored) as `MSSQL_SA_PASSWORD` — never hardcode it in a tracked file.

```bash
export $(grep -v '^#' .env | xargs)     # load the password

# start the stack (Colima must be up first)
colima start && docker start sqlserver

# run a script  (paths are CONTAINER paths — the repo is mounted at /project)
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -i /project/scripts/init_database.sql

# run an ad-hoc query
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -W -Q "SELECT name FROM sys.schemas;"

# shut down when done (frees ~3GB)
docker stop sqlserver && colima stop
```

`sqlcmd` flags: `-C` trusts the self-signed cert (required), `-b` aborts on error (use in scripts so
failures don't pass silently), `-W` trims column padding.

**`BULK INSERT` runs inside the container** and cannot see the host filesystem. Always use
`/project/datasets/...` paths, never `/Users/mac/...`.

GUI clients: SSMS is Windows-only. Use Azure Data Studio, DBeaver, or the VS Code `mssql` extension.

### Status

- [x] Colima + SQL Server 2022 container running
- [x] `datawarehouse` database created, schemas `bronze` / `silver` / `gold` in place
- [x] Source CSVs in `datasets/` (6 files, profiled — see `docs/source_systems_analysis.md`)
- [ ] Bronze DDL + load procedure
- [ ] Bronze quality checks
- [ ] Silver DDL + load procedure
- [ ] Gold star-schema views

## Reference solution

`sql-data-warehouse-project/` is the **completed course repo**, unzipped inside this project. It
contains full solutions for every layer. Treat it as reference only — do not copy from it into
`scripts/`. It should be moved out of this directory or gitignored before committing.

## Environment notes

- The git repository root is `/Users/mac/Desktop`, not this folder — the entire Desktop is tracked.
  Consider a dedicated repo for this project before committing.
