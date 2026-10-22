/*
===============================================================================
Create Database and Schemas  (PostgreSQL)
===============================================================================
Purpose:
    Creates the 'datawarehouse' database and its three medallion schemas:
    bronze, silver, and gold.

Usage (from the repo root, connected to any other database, e.g. postgres):
    psql -d postgres -f scripts/init_database.sql

WARNING:
    This script DROPS the 'datawarehouse' database if it already exists.
    All data in it is permanently lost. Make sure you have backups of anything
    you care about before running.
===============================================================================
*/

-- WITH (FORCE) disconnects any open sessions first (PostgreSQL 13+);
-- otherwise the DROP fails while an idle client is still connected.
DROP DATABASE IF EXISTS datawarehouse WITH (FORCE);
CREATE DATABASE datawarehouse;

\c datawarehouse

-- One schema per medallion layer. Schemas (rather than name prefixes in a
-- single schema) make the layer boundary enforceable and make the layer of any
-- object obvious from its fully-qualified name.
CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;
