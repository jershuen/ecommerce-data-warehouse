/*
===========================================================================================
DDL Script: Create Bronze Tables
===========================================================================================
Script Purpose: 
  This script creates 9 tables for each of the 9 csv files in the Bronze schema. 
  If the table already exists, then it will be dropped first to avoid duplication. 
===========================================================================================
*/

-- Create 5 tables from E-commerce Marketplace Platform
IF OBJECT_ID('bronze.ecom_customers', 'U') IS NOT NULL
	DROP TABLE bronze.ecom_customers;
CREATE TABLE bronze.ecom_customers(
customer_id NVARCHAR(50),
customer_unique_id NVARCHAR(50),
customer_zip_code_prefix NVARCHAR(50),
customer_city NVARCHAR(50),
customer_state NVARCHAR(50)
);

IF OBJECT_ID('bronze.ecom_order_items', 'U') IS NOT NULL
	DROP TABLE bronze.ecom_order_items;
CREATE TABLE bronze.ecom_order_items(
order_id NVARCHAR(50),
order_item_id INT,
product_id NVARCHAR(50),
seller_id NVARCHAR(50),
shipping_limit_date DATE,
price FLOAT,
freight_value FLOAT
);

IF OBJECT_ID('bronze.ecom_order_payments', 'U') IS NOT NULL
	DROP TABLE bronze.ecom_order_payments;
CREATE TABLE bronze.ecom_order_payments(
order_id NVARCHAR(50),
payment_sequential INT,
payment_type NVARCHAR(50),
payment_installments INT,
payment_value FLOAT
);

IF OBJECT_ID('bronze.ecom_order_reviews', 'U') IS NOT NULL
	DROP TABLE bronze.ecom_order_reviews;
CREATE TABLE bronze.ecom_order_reviews(
review_id NVARCHAR(50),
order_id NVARCHAR(50),
review_score INT,
review_comment_title NVARCHAR(50),
review_comment_message NVARCHAR(500),
review_creation_date DATE,
review_answer_timestamp DATETIME2
);

IF OBJECT_ID('bronze.ecom_orders', 'U') IS NOT NULL
	DROP TABLE bronze.ecom_orders;
CREATE TABLE bronze.ecom_orders(
order_id NVARCHAR(50),
customer_id NVARCHAR(50),
order_status NVARCHAR(50),
order_purchase_timestamp DATETIME2,
order_approved_at DATETIME2,
order_delivered_carrier_date DATETIME2,
order_delivered_customer_date DATETIME2,
order_estimated_delivery_date DATE
);

-- Create 2 tables from Product Information Management Platform
IF OBJECT_ID('bronze.pim_products', 'U') IS NOT NULL
	DROP TABLE bronze.pim_products;
CREATE TABLE bronze.pim_products(
product_id NVARCHAR(50),
product_category_name NVARCHAR(50),
product_name_length INT,
product_description_length INT,
product_photos_qty INT,
product_weight_g INT,
product_length_cm INT,
product_height_cm INT,
product_width_cm INT
);

IF OBJECT_ID('bronze.pim_product_category_name_translation', 'U') IS NOT NULL
	DROP TABLE bronze.pim_product_category_name_translation;
CREATE TABLE bronze.pim_product_category_name_translation(
product_category_name NVARCHAR(50),
product_category_name_english NVARCHAR(50)
);

-- Create 2 tables from Seller & Logistics Management Platform
IF OBJECT_ID('bronze.slm_geolocation', 'U') IS NOT NULL
	DROP TABLE bronze.slm_geolocation;
CREATE TABLE bronze.slm_geolocation(
geolocation_zip_code_prefix NVARCHAR(50),
geolocation_lat FLOAT,
geolocation_lng FLOAT,
geolocation_city NVARCHAR(50),
geolocation_state NVARCHAR(50)
);

IF OBJECT_ID('bronze.slm_sellers', 'U') IS NOT NULL
	DROP TABLE bronze.slm_sellers;
CREATE TABLE bronze.slm_sellers(
seller_id NVARCHAR(50),
seller_zip_code_prefix NVARCHAR(50),
seller_city NVARCHAR(50),
seller_state NVARCHAR(50)
);
