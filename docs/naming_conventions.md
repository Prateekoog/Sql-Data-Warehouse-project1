# Naming Conventions

Rules for naming every object in the warehouse — databases, schemas, tables, columns, and stored
procedures. Consistency here is what lets someone read a name and know which layer it belongs to,
where it came from, and what it contains.

## General principles

| Rule | Detail |
|---|---|
| **Case** | `snake_case` — lowercase, underscores between words. Never camelCase, never spaces. |
| **Language** | English throughout. |
| **Reserved words** | Never use SQL reserved words as object names (`order`, `user`, `date`, `key`, `group`). |
| **Abbreviations** | Only where the *source system* already abbreviates. Don't invent new ones. |
| **Plurality** | Dimensions and facts are plural (`dim_customers`, `fact_sales`). Source-layer tables keep the source's own convention. |

## Tables

### Bronze & Silver — `<source_system>_<entity>`

```
crm_cust_info        erp_cust_az12
crm_prd_info         erp_loc_a101
crm_sales_details    erp_px_cat_g1v2
```

- `<source_system>` — short code for the origin system: `crm`, `erp`.
- `<entity>` — **the exact table name from the source system.** Do not rename, do not beautify,
  do not translate `az12` into something friendlier.

**Why keep ugly source names?** Traceability. Bronze exists for debugging, and the fastest possible
debug loop is when the warehouse table name is literally the source file name. The moment you rename
`erp_loc_a101` to `erp_locations`, every investigation gains a translation step. Renaming happens
exactly once — at the boundary into gold.

Silver reuses bronze's table names deliberately: the same object at a different quality level, so a
diff between layers is a diff in *cleanliness*, never in naming.

### Gold — `<category>_<entity>`

Names here are business-friendly, because business users read them.

```
dim_customers        fact_sales        report_sales_monthly
dim_products
```

| Prefix | Meaning |
|---|---|
| `dim_` | Dimension table — descriptive context (who, what, where, when) |
| `fact_` | Fact table — measurable business events |
| `agg_` | Aggregated table — pre-summarized measures |
| `report_` | Flat, report-ready output |

## Columns

### Surrogate keys — `<entity>_key`

```sql
customer_key    -- surrogate key in dim_customers
product_key     -- surrogate key in dim_products
```

Meaningless warehouse-generated integers, used as join keys between facts and dimensions.

### Business keys — `<entity>_id`

```sql
customer_id     -- the real identifier from the source system
```

Kept alongside the surrogate key for traceability back to the source.

### Technical columns — `dwh_<column>`

Metadata created by the warehouse itself, never sourced from a source system. The `dwh_` prefix
makes it immediately obvious a column is plumbing rather than business data.

```sql
dwh_create_date    -- when the warehouse loaded this row
```

## Stored procedures

### `load_<layer>`

```sql
load_bronze
load_silver
```

One loading procedure per layer, named for the layer it fills.

## Quick reference

| Object | Pattern | Example |
|---|---|---|
| Database | single word | `datawarehouse` |
| Schema | layer name | `bronze`, `silver`, `gold` |
| Bronze/silver table | `<source>_<entity>` | `crm_cust_info` |
| Gold dimension | `dim_<entity>` | `dim_customers` |
| Gold fact | `fact_<entity>` | `fact_sales` |
| Gold aggregate | `agg_<entity>` | `agg_sales_monthly` |
| Surrogate key | `<entity>_key` | `customer_key` |
| Business key | `<entity>_id` | `customer_id` |
| Technical column | `dwh_<column>` | `dwh_create_date` |
| Load procedure | `load_<layer>` | `load_bronze` |
