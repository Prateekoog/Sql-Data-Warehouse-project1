# Source Systems Analysis

Profiling of the six source files before any ingestion. Everything below was measured against the
actual CSVs in `datasets/`, not assumed.

## Source system interview

The standard questions you'd put to a source-system owner. There is no owner to interview here, so
these are answered from the files themselves and from the project brief.

### Business context & ownership

| Question | Answer |
|---|---|
| Who owns the data? | Two notional systems — a CRM (customers, products, sales) and an ERP (customer demographics, location, product categories). No live owner; files are handed over. |
| What business process does it support? | Order-to-cash for a bicycle retailer — customers place orders for products sold by the business. |
| System & data documentation | None provided. This document is the substitute. |
| Data model & catalog | None provided. Reconstructed by profiling; catalog to be written for gold. |

### Architecture & technology stack

| Question | Answer |
|---|---|
| How is data stored? | Flat CSV files. No database access, no API. |
| Integration capabilities | File extract only — files in folders. Rules out CDC, event streaming, and direct DB querying. |

### Extract & load

| Question | Answer |
|---|---|
| Incremental vs full load? | **Full.** The brief requires no historization, and the files carry no change markers or watermark column. |
| Data scope & historical needs | Latest snapshot only. No history retained. |
| Expected size of extracts | Small — ~116k rows, 5.4 MB total. Largest file is `sales_details.csv` at 3.4 MB. |
| Data volume limitations | None at this size. Whole-dataset reload completes in under a second. |
| How to avoid impacting source performance? | Not applicable — reading files, not querying a live system. This is the main reason file extracts are used in practice. |
| Authentication & authorization | None required. Local filesystem access via a container mount. |

## Inventory

| Source | File | Rows | Grain |
|---|---|---|---|
| CRM | `cust_info.csv` | 18,494 | One row per customer |
| CRM | `prd_info.csv` | 397 | One row per product *version* (start/end dated) |
| CRM | `sales_details.csv` | 60,398 | One row per product line on an order |
| ERP | `CUST_AZ12.csv` | 18,484 | One row per customer (birthdate + gender) |
| ERP | `LOC_A101.csv` | 18,484 | One row per customer (country) |
| ERP | `PX_CAT_G1V2.csv` | 37 | One row per product category |

Interface for all six: CSV files in folders. Full extract, pull, file parsing.

## How the two systems join

Neither system shares a key format with the other. Both bridges need string surgery.

### Customers

```
CRM  cust_info.cst_key   →  AW00011000
ERP  CUST_AZ12.CID       →  NASAW00011000     strip leading 'NAS'
ERP  LOC_A101.CID        →  AW-00011000       remove '-'
```

Verified: **18,484 of 18,488** CRM customer keys match both ERP files after normalization. The
4 unmatched are the blank-`cst_id` rows (see defects below).

### Products

`prd_key` is a composite that must be split — it carries two different foreign keys:

```
prd_key = 'CO-RF-FR-R92B-58'
          └───┘ └──────────┘
        chars 1-5    chars 7+
            │            │
            │            └─→  sales_details.sls_prd_key
            └─→ replace '-' with '_'  →  'CO_RF'  →  PX_CAT_G1V2.ID
```

Verified: 36 of 37 categories are referenced (one category has no products); **all 130** distinct
`sls_prd_key` values in sales resolve to a product.

## Data quality defects

Each of these is a transformation silver must perform. Nothing here is fixed in bronze.

### `crm_cust_info` — 18,494 rows

| Defect | Count | Fix in silver |
|---|---|---|
| Duplicate `cst_id` | 6 ids (2–3 rows each) | Keep the latest by `cst_create_date` — `ROW_NUMBER()` window, take rank 1 |
| **Junk rows** — no `cst_id`, garbage `cst_key` (`SF566`, `PO25`, `13451235`, `A01Ass`), every other field blank | 4 rows | Dropped by the dedupe filter. Preserved in bronze — asserted by a quality check, since losing them would mean bronze is silently cleaning. |
| Leading/trailing spaces in names | 29 rows | `TRIM()` on first and last name |
| `cst_gndr` blank | 4,578 | Map to `'n/a'`; expand `M`/`F` → `Male`/`Female` |
| `cst_marital_status` blank | 7 | Map to `'n/a'`; expand `M`/`S` → `Married`/`Single` |

### `crm_prd_info` — 397 rows

| Defect | Count | Fix in silver |
|---|---|---|
| `prd_key` is composite | all | Split into `cat_id` (chars 1–5, `-`→`_`) and `prd_key` (chars 7+) |
| `prd_cost` blank | 2 | `ISNULL(..., 0)` |
| `prd_line` has trailing space, coded | all | `TRIM()`, then map `R`/`M`/`S`/`T` → Road/Mountain/Other Sales/Touring |
| `prd_line` blank | 17 | Map to `'n/a'` |
| **`prd_end_dt` earlier than `prd_start_dt`** | **200** | Dates are wrong, not just missing. Recalculate: end date = next version's start date − 1 day, via `LEAD()` over `prd_key` ordered by `prd_start_dt` |
| `prd_end_dt` blank | 197 | Current version — stays NULL after recalculation |

The 200 inverted date ranges are the most interesting defect in the dataset: over half the table.
They can't be repaired in isolation — the correct end date only exists in the *next* row.

### `crm_sales_details` — 60,398 rows

| Defect | Count | Fix in silver |
|---|---|---|
| Dates stored as `INT` (`20101229`), not dates | all | Cast to `DATE` via `NVARCHAR` |
| `sls_order_dt` = `0` or wrong length | 19 | `NULL` when `0` or `LEN <> 8` |
| `sls_sales` ≠ `sls_quantity` × `sls_price` | 20 | Recalculate `sales = quantity * ABS(price)` |
| `sls_sales` / `sls_price` null or unparseable | 15 | Derive `price = sales / quantity` when missing |
| `sls_sales` or `sls_price` ≤ 0 | 10 | `ABS()`, then recalculate |

Rule applied: **quantity is trusted; sales and price are derived.** Where the three disagree,
quantity wins.

### `erp_cust_az12` — 18,484 rows

| Defect | Count | Fix in silver |
|---|---|---|
| `CID` prefixed `NAS` | 11,042 | Strip the first 3 chars when present |
| `GEN` inconsistent — `Male`/`M`/`M `/`F`/`Female`/`F `/blank/whitespace | 9 distinct values | `TRIM()` + `UPPER()`, map to `Male`/`Female`/`'n/a'` |
| `BDATE` in the future | 16 | `NULL` when later than today |
| `BDATE` before 1925 | 17 | Retained — implausible but not impossible; flagged, not deleted |

### `erp_loc_a101` — 18,484 rows

| Defect | Count | Fix in silver |
|---|---|---|
| `CID` contains `-` | all | `REPLACE(cid, '-', '')` |
| `CNTRY` inconsistent — `US`/`USA`/`United States`, `DE`/`Germany` | 13 distinct values for ~6 countries | `TRIM()` + map to full names |
| `CNTRY` blank or whitespace-only | 337 | Map to `'n/a'` |

### `erp_px_cat_g1v2` — 37 rows

Clean. No defects found — `CAT`, `SUBCAT`, `MAINTENANCE` are all consistent. Loads as-is.

## File format issue found during ingestion

Three files — `cust_info.csv`, `CUST_AZ12.csv`, `PX_CAT_G1V2.csv` — had **no trailing newline** on
their final line. `BULK INSERT` with `ROWTERMINATOR = '0x0d0a'` silently discards a final row that
has no terminator: no error, no warning, one row short.

Fixed by appending `\r\n` to each of the three files. No data value was altered.

This is worth knowing generally — the failure is invisible unless you compare row counts against the
source. `tests/quality_checks_bronze.sql` asserts exact expected counts for precisely this reason.
**A count exactly one short is almost always this.**

## Summary of standardization rules

Two conventions applied across every table, so gold is predictable:

1. **Blanks and unknowns become `'n/a'`**, never empty string, never NULL, for descriptive columns.
2. **Coded values are expanded to readable text** (`M` → `Male`, `R` → `Road`, `US` → `United States`)
   — gold is read by business users, and the expansion belongs in silver so every consumer gets it.
