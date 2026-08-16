/*
===============================================================================
Stored Procedure: bronze.load_bronze
===============================================================================
Purpose:
    Loads all six source CSVs into the bronze layer.

    Full load, truncate & insert: every run wipes each table and reloads it from
    the source file. No incremental logic — the brief requires no historization.

Parameters:
    None.

Usage:
    EXEC bronze.load_bronze;

Notes:
    - BULK INSERT executes INSIDE the SQL Server container and cannot see the
      host filesystem. Paths below are container paths; the repo is mounted at
      /project. On a Windows host these would be C:\... paths instead.
    - ROWTERMINATOR is '0x0d0a' (CRLF) because the source files are CRLF.
      A file whose final line lacks a terminator will silently lose that row —
      three of these files originally did, and were fixed by appending CRLF.
      If a row count ever comes up exactly one short, check this first.
    - Empty CSV fields become NULL (no KEEPNULLS needed): with no column default
      defined, BULK INSERT applies NULL. Blank numerics therefore stay NULL
      rather than being fabricated as 0.
    - Each load prints its duration, and the whole run prints a total, so a
      slow file is visible without instrumenting anything.
===============================================================================
*/

USE datawarehouse;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @start_time      DATETIME,
            @end_time        DATETIME,
            @batch_start     DATETIME,
            @batch_end       DATETIME;

    BEGIN TRY
        SET @batch_start = GETDATE();

        PRINT '==========================================================';
        PRINT 'Loading Bronze Layer';
        PRINT '==========================================================';

        -- ------------------------------------------------------------
        PRINT '';
        PRINT '--- CRM Tables ---';
        -- ------------------------------------------------------------

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.crm_cust_info';
        TRUNCATE TABLE bronze.crm_cust_info;
        PRINT '>> Inserting:  bronze.crm_cust_info';
        BULK INSERT bronze.crm_cust_info
        FROM '/project/datasets/source_crm/cust_info.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.crm_prd_info';
        TRUNCATE TABLE bronze.crm_prd_info;
        PRINT '>> Inserting:  bronze.crm_prd_info';
        BULK INSERT bronze.crm_prd_info
        FROM '/project/datasets/source_crm/prd_info.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.crm_sales_details';
        TRUNCATE TABLE bronze.crm_sales_details;
        PRINT '>> Inserting:  bronze.crm_sales_details';
        BULK INSERT bronze.crm_sales_details
        FROM '/project/datasets/source_crm/sales_details.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        -- ------------------------------------------------------------
        PRINT '';
        PRINT '--- ERP Tables ---';
        -- ------------------------------------------------------------

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.erp_cust_az12';
        TRUNCATE TABLE bronze.erp_cust_az12;
        PRINT '>> Inserting:  bronze.erp_cust_az12';
        BULK INSERT bronze.erp_cust_az12
        FROM '/project/datasets/source_erp/CUST_AZ12.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.erp_loc_a101';
        TRUNCATE TABLE bronze.erp_loc_a101;
        PRINT '>> Inserting:  bronze.erp_loc_a101';
        BULK INSERT bronze.erp_loc_a101
        FROM '/project/datasets/source_erp/LOC_A101.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        SET @start_time = GETDATE();
        PRINT '>> Truncating: bronze.erp_px_cat_g1v2';
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;
        PRINT '>> Inserting:  bronze.erp_px_cat_g1v2';
        BULK INSERT bronze.erp_px_cat_g1v2
        FROM '/project/datasets/source_erp/PX_CAT_G1V2.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '   Duration: ' + CAST(DATEDIFF(ms, @start_time, @end_time) AS NVARCHAR) + ' ms';

        SET @batch_end = GETDATE();
        PRINT '';
        PRINT '==========================================================';
        PRINT 'Bronze Layer loaded successfully';
        PRINT 'Total duration: ' + CAST(DATEDIFF(ms, @batch_start, @batch_end) AS NVARCHAR) + ' ms';
        PRINT '==========================================================';

    END TRY
    BEGIN CATCH
        PRINT '';
        PRINT '==========================================================';
        PRINT 'ERROR LOADING BRONZE LAYER';
        PRINT 'Message : ' + ERROR_MESSAGE();
        PRINT 'Number  : ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'State   : ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT 'Line    : ' + CAST(ERROR_LINE() AS NVARCHAR);
        PRINT '==========================================================';
        THROW;   -- re-raise so callers and sqlcmd -b see a non-zero exit
    END CATCH
END;
GO
