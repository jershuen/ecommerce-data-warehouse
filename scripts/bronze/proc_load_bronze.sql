/*
===========================================================================================
Stored Procedure: Load Bronze Layer (from source to Bronze)
===========================================================================================
Script Purpose:
  This script creates the stored procedure called 'bronze.load_bronze' to be executed to load data into the Bronze schema from the 9 CSV files using 'BULK INSERT'.
  It truncates tables first before adding data in them, to avoid duplication.
  Additionally, it prints out stage, status and duration in each process, allowing for easier debugging.

Usage Example:
  EXEC bronze.load_bronze
===========================================================================================
*/


CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY
		SET @batch_start_time = GETDATE();
		PRINT '===========================================';
		PRINT 'Loading Bronze Layer';
		PRINT '===========================================';

		PRINT '-------------------------------------------';
		PRINT 'Loading E-commerce system Tables';
		PRINT '-------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.ecom_customers';
		TRUNCATE TABLE bronze.ecom_customers;
		PRINT '>> Inserting Data into: bronze.ecom_customers';
		BULK INSERT bronze.ecom_customers
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\ecommerce_system\olist_customers_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.ecom_order_items';
		TRUNCATE TABLE bronze.ecom_order_items;
		PRINT '>> Inserting Data into: bronze.ecom_order_items';
		BULK INSERT bronze.ecom_order_items
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\ecommerce_system\olist_order_items_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.ecom_order_payments';
		TRUNCATE TABLE bronze.ecom_order_payments;
		PRINT '>> Inserting Data into: bronze.ecom_order_payments';
		BULK INSERT bronze.ecom_order_payments
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\ecommerce_system\olist_order_payments_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.ecom_order_reviews';
		TRUNCATE TABLE bronze.ecom_order_reviews;
		PRINT '>> Inserting Data into: bronze.ecom_order_reviews';
		BULK INSERT bronze.ecom_order_reviews
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\ecommerce_system\olist_order_reviews_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '\n',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bbronze.ecom_orders';
		TRUNCATE TABLE bronze.ecom_orders;
		PRINT '>> Inserting Data into: bronze.ecom_orders';
		BULK INSERT bronze.ecom_orders
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\ecommerce_system\olist_orders_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'
	
		PRINT '----------------------------------------------------------';
		PRINT 'Loading Product Information Management Platform Tables';
		PRINT '----------------------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Tuncating Table: bronze.pim_products';
		TRUNCATE TABLE bronze.pim_products;
		PRINT '>> Inserting Data into: bronze.pim_products';
		BULK INSERT bronze.pim_products
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\product_information_system\olist_products_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Tuncating Table: bronze.pim_product_category_name_translation';
		TRUNCATE TABLE bronze.pim_product_category_name_translation;
		PRINT '>> Inserting Data into: bronze.pim_product_category_name_translation';
		BULK INSERT bronze.pim_product_category_name_translation
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\product_information_system\product_category_name_translation.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		PRINT '----------------------------------------------------------';
		PRINT 'Loading Seller & Logistics Management Platform Tables';
		PRINT '----------------------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.slm_geolocation';
		TRUNCATE TABLE bronze.slm_geolocation;
		PRINT '>> Inserting Data into: bronze.slm_geolocation';
		BULK INSERT bronze.slm_geolocation
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\seller_logistic_system\olist_geolocation_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------'

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.slm_sellers';
		TRUNCATE TABLE bronze.slm_sellers;
		PRINT '>> Inserting Data into: bronze.slm_sellers';
		BULK INSERT bronze.slm_sellers
		FROM 'C:\Users\user\Desktop\self projects\Olist Ecommerce dataset\source data\seller_logistic_system\olist_sellers_dataset.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR = '0x0A',
			TABLOCK,
			FORMAT = 'CSV'
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST (DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------';
		
		SET @batch_end_time = GETDATE();
		PRINT '===========================================';
		PRINT 'Loading Bronze Layer is completed';
		PRINT '	- Total Load Duration: ' + CAST (DATEDIFF(second, @batch_start_time, @batch_end_time) AS NVARCHAR) + 'seconds';

	END TRY
	BEGIN CATCH
		PRINT '==========================================';
		PRINT 'Error occured during loading Bronze Layer';
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST(ERROR_STATE() AS NVARCHAR);
		PRINT '==========================================';
	END CATCH
END
