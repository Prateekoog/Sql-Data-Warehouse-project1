/*
===============================================================================
DDL Script: Create Bronze Tables
===============================================================================
Purpose:
    Defines the six bronze tables — one per source file, mirroring each source's
    structure exactly. Drops and recreates them, so the script is re-runnable.

Design notes:
    - Column names and order match the source CSVs exactly. No renaming.
    - Types are the source's own representation, not the "correct" one.
      sls_order_dt / sls_ship_dt / sls_due_dt arrive as INT (20101229) and stay
      INT here. Casting them to DATE is a transformation, and transformation
      belongs in silver.
    - Every column is nullable. Bronze must never reject a row for a data
      quality reason — capturing the defect is the whole point.

WARNING:
    Running this drops all bronze tables and their data.
===============================================================================
*/

USE datawarehouse;
GO

-- ============================================================
-- CRM source
-- ============================================================

DROP TABLE IF EXISTS bronze.crm_cust_info;
GO
CREATE TABLE bronze.crm_cust_info (
    cst_id              INT,
    cst_key             NVARCHAR(50),
    cst_firstname       NVARCHAR(50),
    cst_lastname        NVARCHAR(50),
    cst_marital_status  NVARCHAR(50),
    cst_gndr            NVARCHAR(50),
    cst_create_date     DATE
);
GO

DROP TABLE IF EXISTS bronze.crm_prd_info;
GO
CREATE TABLE bronze.crm_prd_info (
    prd_id        INT,
    prd_key       NVARCHAR(50),
    prd_nm        NVARCHAR(50),
    prd_cost      INT,
    prd_line      NVARCHAR(50),
    prd_start_dt  DATE,
    prd_end_dt    DATE
);
GO

DROP TABLE IF EXISTS bronze.crm_sales_details;
GO
CREATE TABLE bronze.crm_sales_details (
    sls_ord_num   NVARCHAR(50),
    sls_prd_key   NVARCHAR(50),
    sls_cust_id   INT,
    sls_order_dt  INT,          -- yyyymmdd as an integer; cast in silver
    sls_ship_dt   INT,
    sls_due_dt    INT,
    sls_sales     INT,
    sls_quantity  INT,
    sls_price     INT
);
GO

-- ============================================================
-- ERP source
-- ============================================================

DROP TABLE IF EXISTS bronze.erp_cust_az12;
GO
CREATE TABLE bronze.erp_cust_az12 (
    cid    NVARCHAR(50),
    bdate  DATE,
    gen    NVARCHAR(50)
);
GO

DROP TABLE IF EXISTS bronze.erp_loc_a101;
GO
CREATE TABLE bronze.erp_loc_a101 (
    cid    NVARCHAR(50),
    cntry  NVARCHAR(50)
);
GO

DROP TABLE IF EXISTS bronze.erp_px_cat_g1v2;
GO
CREATE TABLE bronze.erp_px_cat_g1v2 (
    id           NVARCHAR(50),
    cat          NVARCHAR(50),
    subcat       NVARCHAR(50),
    maintenance  NVARCHAR(50)
);
GO
