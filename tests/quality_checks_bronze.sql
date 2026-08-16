/*
===============================================================================
Quality Checks: Bronze Layer
===============================================================================
Purpose:
    Verifies the bronze load was COMPLETE and STRUCTURALLY correct.

    Bronze is raw by design, so this script does NOT check whether the data is
    clean — duplicates, bad dates and inconsistent codes are all expected here
    and are silver's problem. What it checks is that ingestion did not lose,
    duplicate, or mangle anything.

Usage:
    Run after EXEC bronze.load_bronze;
    Every check prints PASS or FAIL. Investigate any FAIL before building silver.
===============================================================================
*/

USE datawarehouse;
GO

PRINT '==========================================================';
PRINT 'Bronze Quality Checks';
PRINT '==========================================================';

-- ============================================================
-- Check 1: Row completeness
-- Expected counts are the source files' data rows (excluding header).
-- A count exactly one short usually means the file's final line lacks a
-- CRLF terminator — BULK INSERT drops it silently.
-- ============================================================
PRINT '';
PRINT '--- Check 1: Row counts vs source files ---';

;WITH expected AS (
    SELECT 'crm_cust_info'     AS tbl, 18494 AS expected_rows
    UNION ALL SELECT 'crm_prd_info',        397
    UNION ALL SELECT 'crm_sales_details', 60398
    UNION ALL SELECT 'erp_cust_az12',     18484
    UNION ALL SELECT 'erp_loc_a101',      18484
    UNION ALL SELECT 'erp_px_cat_g1v2',      37
),
actual AS (
    SELECT 'crm_cust_info'     AS tbl, COUNT(*) AS actual_rows FROM bronze.crm_cust_info
    UNION ALL SELECT 'crm_prd_info',      COUNT(*) FROM bronze.crm_prd_info
    UNION ALL SELECT 'crm_sales_details', COUNT(*) FROM bronze.crm_sales_details
    UNION ALL SELECT 'erp_cust_az12',     COUNT(*) FROM bronze.erp_cust_az12
    UNION ALL SELECT 'erp_loc_a101',      COUNT(*) FROM bronze.erp_loc_a101
    UNION ALL SELECT 'erp_px_cat_g1v2',   COUNT(*) FROM bronze.erp_px_cat_g1v2
)
SELECT  e.tbl,
        e.expected_rows,
        a.actual_rows,
        CASE WHEN e.expected_rows = a.actual_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM    expected e
JOIN    actual   a ON a.tbl = e.tbl
ORDER BY e.tbl;

-- ============================================================
-- Check 2: No table loaded empty
-- Catches a silently failed BULK INSERT or a wrong file path.
-- ============================================================
PRINT '';
PRINT '--- Check 2: No empty tables ---';

SELECT  t.name AS tbl,
        SUM(p.rows) AS row_count,
        CASE WHEN SUM(p.rows) > 0 THEN 'PASS' ELSE 'FAIL - table is empty' END AS result
FROM    sys.tables t
JOIN    sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE   t.schema_id = SCHEMA_ID('bronze')
GROUP BY t.name
ORDER BY t.name;

-- ============================================================
-- Check 3: Column shift detection
-- If FIELDTERMINATOR or ROWTERMINATOR were wrong, values land in the wrong
-- columns. These assertions test that each key column still holds the KIND of
-- value it should — a cheap smoke test for misalignment.
-- ============================================================
PRINT '';
PRINT '--- Check 3: Columns hold the expected kind of value ---';

-- Every REAL customer row (one with a cst_id) must have an AW-prefixed key.
-- The 4 junk rows in the source have no cst_id and a garbage key; they are
-- asserted separately in Check 4, since preserving them is correct behaviour.
SELECT 'crm_cust_info.cst_key starts with AW (rows with a cst_id)' AS assertion,
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL AND cst_key NOT LIKE 'AW%')
       THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'crm_sales_details.sls_ord_num starts with SO',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM bronze.crm_sales_details
            WHERE sls_ord_num IS NOT NULL AND sls_ord_num NOT LIKE 'SO%')
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'crm_sales_details date columns are 8-digit yyyymmdd or 0',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM bronze.crm_sales_details
            WHERE sls_due_dt IS NOT NULL
              AND sls_due_dt <> 0
              AND (sls_due_dt < 19000101 OR sls_due_dt > 21001231))
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'erp_px_cat_g1v2.maintenance is only Yes/No',
       CASE WHEN NOT EXISTS (
            SELECT 1 FROM bronze.erp_px_cat_g1v2
            WHERE maintenance NOT IN ('Yes','No'))
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'erp_loc_a101.cid contains a dash (format preserved)',
       CASE WHEN EXISTS (
            SELECT 1 FROM bronze.erp_loc_a101 WHERE cid LIKE '%-%')
       THEN 'PASS' ELSE 'FAIL' END;

-- ============================================================
-- Check 4: Raw defects PRESERVED, not silently repaired
-- Bronze's job is faithfulness. These defects were measured in the source
-- files, so they MUST still be present. If any of these "improved", bronze
-- is transforming data and violating the architecture.
-- ============================================================
PRINT '';
PRINT '--- Check 4: Source defects preserved (bronze must not clean) ---';

SELECT 'duplicate/blank cst_id still present' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM bronze.crm_cust_info) >
                 (SELECT COUNT(DISTINCT cst_id) FROM bronze.crm_cust_info WHERE cst_id IS NOT NULL)
       THEN 'PASS' ELSE 'FAIL - duplicates disappeared' END AS result
UNION ALL
SELECT 'untrimmed names still present',
       CASE WHEN EXISTS (
            SELECT 1 FROM bronze.crm_cust_info
            WHERE cst_firstname <> TRIM(cst_firstname) OR cst_lastname <> TRIM(cst_lastname))
       THEN 'PASS' ELSE 'FAIL - names were trimmed' END
UNION ALL
SELECT 'inverted product date ranges still present',
       CASE WHEN EXISTS (
            SELECT 1 FROM bronze.crm_prd_info WHERE prd_end_dt < prd_start_dt)
       THEN 'PASS' ELSE 'FAIL - dates were corrected' END
UNION ALL
SELECT 'zero order dates still present',
       CASE WHEN EXISTS (
            SELECT 1 FROM bronze.crm_sales_details WHERE sls_order_dt = 0)
       THEN 'PASS' ELSE 'FAIL - zero dates were cleaned' END
UNION ALL
SELECT 'NAS-prefixed erp cids still present',
       CASE WHEN EXISTS (
            SELECT 1 FROM bronze.erp_cust_az12 WHERE cid LIKE 'NAS%')
       THEN 'PASS' ELSE 'FAIL - prefix was stripped' END
UNION ALL
SELECT 'inconsistent country codes still present',
       CASE WHEN (SELECT COUNT(DISTINCT cntry) FROM bronze.erp_loc_a101) > 6
       THEN 'PASS' ELSE 'FAIL - countries were standardized' END
UNION ALL
-- 4 junk rows exist in cust_info.csv: no cst_id, a garbage cst_key
-- (SF566, PO25, 13451235, A01Ass), every other field blank. Bronze must keep
-- them; silver drops them during deduplication.
SELECT '4 junk customer rows preserved',
       CASE WHEN (SELECT COUNT(*) FROM bronze.crm_cust_info
                  WHERE cst_id IS NULL AND cst_key IS NOT NULL) = 4
       THEN 'PASS' ELSE 'FAIL - junk rows lost or altered' END;

-- ============================================================
-- Check 5: Blank numerics are NULL, not fabricated zeros
-- BULK INSERT applies the column default to an empty field; with no default
-- defined that is NULL. A 0 here would be an invented value.
-- ============================================================
PRINT '';
PRINT '--- Check 5: Missing numerics are NULL, not 0 ---';

SELECT 'crm_cust_info.cst_id blanks are NULL' AS assertion,
       CASE WHEN (SELECT COUNT(*) FROM bronze.crm_cust_info WHERE cst_id = 0) = 0
       THEN 'PASS' ELSE 'FAIL - blanks became 0' END AS result
UNION ALL
SELECT 'crm_prd_info.prd_cost blanks are NULL',
       CASE WHEN (SELECT COUNT(*) FROM bronze.crm_prd_info WHERE prd_cost = 0) = 0
       THEN 'PASS' ELSE 'FAIL - blanks became 0' END;

PRINT '';
PRINT '==========================================================';
PRINT 'Bronze quality checks complete';
PRINT '==========================================================';
GO
