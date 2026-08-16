# Source Systems Analysis

Profiling of the six source files before any ingestion. Everything below was measured against the
actual CSVs in `datasets/`, not assumed.

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
| Blank `cst_id` | 4 rows | Filtered out by the same dedupe (rank > 1 / null key) |
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

## Summary of standardization rules

Two conventions applied across every table, so gold is predictable:

1. **Blanks and unknowns become `'n/a'`**, never empty string, never NULL, for descriptive columns.
2. **Coded values are expanded to readable text** (`M` → `Male`, `R` → `Road`, `US` → `United States`)
   — gold is read by business users, and the expansion belongs in silver so every consumer gets it.
