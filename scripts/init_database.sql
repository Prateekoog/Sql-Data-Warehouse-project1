/*
===============================================================================
Create Database and Schemas
===============================================================================
Purpose:
    Creates the 'datawarehouse' database and its three medallion schemas:
    bronze, silver, and gold.

WARNING:
    This script DROPS the 'datawarehouse' database if it already exists.
    All data in it is permanently lost. Make sure you have backups of anything
    you care about before running.
===============================================================================
*/

USE master;
GO

-- Drop and recreate the 'datawarehouse' database.
-- SINGLE_USER WITH ROLLBACK IMMEDIATE forcibly disconnects any open sessions,
-- otherwise the DROP blocks indefinitely on an idle connection.
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'datawarehouse')
BEGIN
    ALTER DATABASE datawarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE datawarehouse;
END;
GO

CREATE DATABASE datawarehouse;
GO

USE datawarehouse;
GO

-- One schema per medallion layer. Schemas (rather than name prefixes in a
-- single schema) make the layer boundary enforceable and make the layer of any
-- object obvious from its fully-qualified name.
CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO
