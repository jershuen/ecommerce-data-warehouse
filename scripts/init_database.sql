
/*
===========================================================================================
Create Database and Schemas
===========================================================================================
Script Purpose:
	This script creates a new database called 'DataWarehouse' after checking if it already exists. 
	If it does, then it is dropped and recreated.
	The script also creates three schemas for 'bronze', 'silver' and 'gold' layers.
Warning:
	This script will drop the database. Please proceed with caution.
===========================================================================================
*/


USE master;
GO

-- Drop and recreate the 'DataWarehouse' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
	ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE DataWarehouse;
END;
GO

-- Create Database 'DataWarehouse
CREATE DATABASE DataWarehouse;
GO
USE DataWarehouse;
GO

-- Create Schemas
CREATE SCHEMA bronze;
GO           
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO
