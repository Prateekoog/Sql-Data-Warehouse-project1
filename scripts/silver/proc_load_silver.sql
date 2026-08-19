TRUNCATE TABLE silver.crm_cust_info;

INSERT INTO silver.crm_cust_info (
    cst_id, cst_key, cst_firstname, cst_lastname,
    cst_marital_status, cst_gndr, cst_create_date
)
SELECT
    cst_id,
    cst_key,
    TRIM(cst_firstname),
    TRIM(cst_lastname),
    CASE
        WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
        ELSE 'n/a'
    END,
    CASE
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'n/a'
    END,
    cst_create_date
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY cst_id ORDER BY cst_create_date DESC
           ) AS rn
    FROM bronze.crm_cust_info
    WHERE cst_id IS NOT NULL
) t
WHERE rn = 1;

TRUNCATE TABLE silver.crm_prd_info;

INSERT INTO silver.crm_prd_info (
    prd_id, prd_key, cat_id, prd_nm, prd_cost, prd_line,
    prd_start_dt, prd_end_dt
)
SELECT
    prd_id,

    
    SUBSTRING(prd_key, 7, LENGTH(prd_key)),

   
    REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),

    TRIM(prd_nm),

    -- NULL cost ko 0
    COALESCE(prd_cost, 0),

    -- code expand
    CASE UPPER(TRIM(prd_line))
        WHEN 'M' THEN 'Mountain'
        WHEN 'R' THEN 'Road'
        WHEN 'S' THEN 'Other Sales'
        WHEN 'T' THEN 'Touring'
        ELSE 'n/a'
    END,

    prd_start_dt::DATE,

    -- agli version ka start date minus 1 din
    (LEAD(prd_start_dt) OVER (
        PARTITION BY prd_key ORDER BY prd_start_dt
    ) - INTERVAL '1 day')::DATE

FROM bronze.crm_prd_info;