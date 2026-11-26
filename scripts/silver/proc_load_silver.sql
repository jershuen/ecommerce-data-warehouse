/* 
=============================================================================
Stored Procedure: Load SILVER LAYER  (Bronze -> Silver)
=============================================================================
Script Purpose:
  This stored procedure performs the ETL process to populate the Silver schema tables 
  from the Bronze schema. 
Actions Performed:
  - Truncates Silver tables
  - Inserts transformed and cleaned data from Bronze into Silver tables

Paratmeters: 
  None. This stored procedure does not accept any parameters or return any values.

Usage Example:
  EXEC silver.load_silver

 NOTE TAGS USED IN COMMENTS
   [i]  INFO               - rationale or context worth remembering

 DATA-QUALITY ASPECT TAGS (tags are abbreviated in the checking file)
   1. [NULL handling]              - genuinely missing vs. not applicable
   2. [Duplicate handling]         - exact / business-key duplicates
   3. [Erroneous data]             - impossible / inconsistent / suspicious
   4. [Data types & formats]       - types, formats, naming conventions
   5. [Date & timestamp validity]  - missing, sequence, suspicious dates
   6. [Referential integrity]      - parent / child relationships
   7. [Business-rule validation]   - records make sense for their context
   8. [Standardisation]            - TRIM, labels, units, representations
   9. [Integration & enrichment]   - combining sources, derived columns

 TABLE PREFIXES (groups tables by domain)
   slm_  : geolocation, sellers
   ecom_ : customers, orders, order_items, order_payments, order_reviews
   pim_  : products, product_category_name_translation
   c_    : columns that are CALCULATED in silver (flags, not source data)

 LOAD ORDER (must be kept - later steps read earlier SILVER tables)
   1. slm_geolocation   <- bronze geolocation + zips seen only in customers/sellers
   2. ecom_customers    <- needs silver.slm_geolocation
   3. slm_sellers       <- needs silver.slm_geolocation
   4. pim_products
   5. pim_product_category_name_translation <- needs silver.pim_products
   6. ecom_orders
   7. ecom_order_items
   8. ecom_order_payments
   9. ecom_order_reviews <- needs silver.ecom_orders

 ============================================================================= */
CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '====================================================';
        PRINT 'Loading Silver Layer';
        PRINT '====================================================';
 
        /* =============================================================================
            1. silver.slm_geolocation
            -----------------------------------------------------------------------------
            Grain   : one row per geolocation_zip_code_prefix (reference table)
            Sources : bronze.slm_geolocation
                        + zip prefixes that exist ONLY in bronze customers / sellers

            Aspects applied:
                      [Duplicate handling]  Bronze has many rows per zip (different lat/lng). Reduced to ONE row
                                            per zip using ROW_NUMBER() (flag = 1 is kept).
                [Integration & enrichment]  Customer/seller zips missing from the reference table are APPENDED
                                            (UNION ALL) so every customer and seller zip has a reference row.
                                            Their lat/lng are NULL because that information does not exist.
                           [NULL handling]  lat/lng NULL here means "genuinely unknown", not "not applicable".
                         [Standardisation]  TRIM() on city and state.

            Checks : silver_checking_organised.sql, section A
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.slm_geolocation'
        PRINT '----------------------------------------------------';

        -- Loading silver.slm_geolocation
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.slm_geolocation';
        IF OBJECT_ID('silver.slm_geolocation', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.slm_geolocation;
        PRINT '>> Inserting Data Into: silver.slm_geolocation';
        INSERT INTO silver.slm_geolocation (
            geolocation_zip_code_prefix,
            geolocation_lat,
            geolocation_lng,
            geolocation_city,
            geolocation_state,
            c_geo_source)


        -- Outer query: keep the winning row per zip and TRIM text   [Standardisation]
        SELECT 
        geolocation_zip_code_prefix, 
        geolocation_lat, 
        geolocation_lng, 
        UPPER(TRIM(geolocation_city)) AS geolocation_city, 
        UPPER(TRIM(geolocation_state)) AS geolocation_state,
        c_geo_source
        FROM(
            -- Middle query: rank rows within each zip, most frequent combination first   [Duplicate handling]
            SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY geolocation_zip_code_prefix ORDER BY COUNT(*) DESC,
                                                                                geolocation_city ASC,
                                                                                geolocation_state ASC,
                                                                                geolocation_lat ASC,
                                                                                geolocation_lng ASC) AS ranked_occurences
            FROM (
                    -- Inner query: stack the three sources   [Integration & enrichment]
                    -- (a) reference table as delivered
                    SELECT 
                    geolocation_zip_code_prefix, 
                    geolocation_lat, 
                    geolocation_lng, 
                    UPPER(TRIM(geolocation_city)) AS geolocation_city, 
                    UPPER(TRIM(geolocation_state)) AS geolocation_state,
                    'Reference' AS c_geo_source
                    FROM bronze.slm_geolocation
                        UNION ALL
                    -- (b) customer zips NOT in the reference table (lat/lng unknown)
                    SELECT 
                    customer_zip_code_prefix,
                    NULL AS geolocation_lat,
                    NULL AS geolocation_lng,
                    UPPER(TRIM(customer_city)),
                    UPPER(TRIM(customer_state)),
                    'Derived' AS c_geo_source
                    FROM bronze.ecom_customers
                    WHERE NOT EXISTS(SELECT 1 
                                        FROM bronze.slm_geolocation g
                                        WHERE g.geolocation_zip_code_prefix=customer_zip_code_prefix)
                        UNION ALL
                    -- (c) seller zips NOT in the reference table (lat/lng unknown)
                    SELECT seller_zip_code_prefix,
                    NULL AS geolocation_lat,
                    NULL AS geolocation_lng,
                    UPPER(TRIM(seller_city)),
                    UPPER(TRIM(seller_state)),
                    'Derived' AS c_geo_source
                    FROM bronze.slm_sellers
                    WHERE NOT EXISTS(SELECT 1
	                                    FROM bronze.slm_geolocation g
                                        WHERE g.geolocation_zip_code_prefix=seller_zip_code_prefix))f
            GROUP BY 
                geolocation_zip_code_prefix, 
                geolocation_lat, 
                geolocation_lng, 
                geolocation_city, 
                geolocation_state,
                c_geo_source)t WHERE ranked_occurences=1
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';

        /* =============================================================================
            2. silver.ecom_customers
            -----------------------------------------------------------------------------
            Grain   : one row per customer_id (one customer_id = one ORDER; the real
                        person is customer_unique_id, who can appear many times)
            Source  : bronze.ecom_customers  LEFT JOIN  silver.slm_geolocation

            Aspects applied:
                [Erroneous data]/[Standardisation] City names disagreed with the reference table for the same zip.
                                                   Evidence-based correction: differences came from (1) special
                                                   characters / accents and (2) incomplete names. The reference city
                                                   is therefore treated as the standard.
                       [Integration & enrichment]  Customer zips that did not exist in the reference table were added
                                                   to silver.slm_geolocation (block 1), so every customer now joins.
                          [Referential integrity]  customer_zip_code_prefix -> silver.slm_geolocation.

            Checks : section B  
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.ecom_customers'
        PRINT '----------------------------------------------------';

        -- Loading silver.ecom_customers
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.ecom_customers'
        IF OBJECT_ID('silver.ecom_customers', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.ecom_customers;
        PRINT '>> Inserting Data Into: silver.ecom_customers';
        INSERT INTO silver.ecom_customers(
            customer_id,
            customer_unique_id,
            customer_zip_code_prefix,
            customer_city,  
            customer_state
            )

        SELECT 
        c.customer_id,
        c.customer_unique_id,
        c.customer_zip_code_prefix,
        -- Standardise city to the reference spelling   [Standardisation][Erroneous data]
        CASE WHEN g.geolocation_city != UPPER(TRIM(c.customer_city))
            THEN g.geolocation_city
            ELSE UPPER(TRIM(c.customer_city))
        END AS customer_city,  
        CASE WHEN g.geolocation_state != UPPER(TRIM(c.customer_state))
            THEN g.geolocation_state
            ELSE UPPER(TRIM(c.customer_state))
        END AS customer_state
        FROM bronze.ecom_customers c LEFT OUTER JOIN
        silver.slm_geolocation g
        ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            3. silver.slm_sellers
            -----------------------------------------------------------------------------
            Grain   : one row per seller_id
            Source  : bronze.slm_sellers  LEFT JOIN  silver.slm_geolocation

            Aspects applied:
                [Standardisation]/[Erroneous data] City AND state are aligned with the reference table (same logic
                                                   and evidence as customers).
                          [Referential integrity]  seller_zip_code_prefix -> silver.slm_geolocation.
 
            Checks : section C
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.slm_sellers'
        PRINT '----------------------------------------------------';

        -- Loading silver.slm_sellers
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.slm_sellers'
        IF OBJECT_ID('silver.slm_sellers', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.slm_sellers;
        PRINT '>> Inserting Data Into: silver.slm_sellers';
        INSERT INTO silver.slm_sellers (
                seller_id,
                seller_zip_code_prefix,
                seller_city,
                seller_state)
        
        SELECT
        s.seller_id,
        s.seller_zip_code_prefix,
        -- Standardise city and state to the reference values   [Standardisation][Erroneous data]
        CASE WHEN g.geolocation_city != UPPER(TRIM(s.seller_city))
            THEN g.geolocation_city
            ELSE UPPER(TRIM(s.seller_city))
        END AS seller_city,
        CASE WHEN g.geolocation_state != UPPER(TRIM(s.seller_state))
            THEN g.geolocation_state
            ELSE UPPER(TRIM(s.seller_state))
        END AS seller_state
        FROM bronze.slm_sellers s LEFT OUTER JOIN
        silver.slm_geolocation g
        ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            4. silver.pim_products
            -----------------------------------------------------------------------------
            Grain   : one row per product_id
            Source  : bronze.pim_products

            Aspects applied:
                    [NULL handling] 611 products have NULLs. They are GENUINELY MISSING (not "not
                                    applicable": every product has a name, a weight, etc.). They are
                                    kept, not deleted, and not imputed (no evidence for a value).
                                    Pattern found:
                                        609 rows : descriptive attributes NULL, physical dims present
                                        1 row  : physical dims NULL, descriptive attributes present
                                        1 row  : everything NULL (product_id 5eb564652db742ff8f28759cd8d2652a)
                  [Erroneous data]  c_metadata_status summarises the pattern so gold can filter easily.
                 [Standardisation]  TRIM() on product_category_name.

            Checks : section D
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.pim_products'
        PRINT '----------------------------------------------------';

        -- Loading silver.pim_products
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.pim_products';
        IF OBJECT_ID('silver.pim_products', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.pim_products;
        PRINT '>> Inserting Data Into: silver.pim_products';
        INSERT INTO silver.pim_products(
            product_id,
            product_category_name,
            product_name_length,
            product_description_length,
            product_photos_qty,
            product_weight_g,
            product_length_cm,
            product_height_cm,
            product_width_cm,
            c_metadata_status)

        SELECT 
        product_id,
        TRIM(product_category_name) AS product_category_name,
        product_name_length,
        product_description_length,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm,
        -- Calculated flag describing WHICH metadata is missing   [NULL handling][Integration & enrichment]
        CASE WHEN product_category_name IS NULL
                AND product_name_length IS NULL
                AND product_description_length IS NULL
                AND product_photos_qty IS NULL
                AND product_weight_g IS NOT NULL
                AND product_length_cm IS NOT NULL
                AND product_height_cm IS NOT NULL
                AND product_width_cm IS NOT NULL
                THEN 'Missing descriptive attributes'
            WHEN product_weight_g IS NULL
                AND product_length_cm IS NULL
                AND product_height_cm IS NULL
                AND product_width_cm IS NULL
                AND product_category_name IS NOT NULL
                AND product_name_length IS NOT NULL
                AND product_description_length IS NOT NULL
                AND product_photos_qty IS NOT NULL
                THEN 'Missing physical dimensions'
            WHEN product_category_name IS NULL
                AND product_name_length IS NULL
                AND product_description_length IS NULL
                AND product_photos_qty IS NULL
                AND product_weight_g IS NULL
                AND product_length_cm IS NULL
                AND product_height_cm IS NULL
                AND product_width_cm IS NULL
                THEN 'Missing all metadata'
            WHEN product_category_name IS NOT NULL 
                AND product_name_length IS NOT NULL AND product_name_length>0
                AND product_description_length IS NOT NULL AND product_description_length>0
                AND product_photos_qty IS NOT NULL AND product_photos_qty>0
                AND product_weight_g IS NOT NULL AND product_weight_g>0
                AND product_length_cm IS NOT NULL AND product_length_cm>0
                AND product_height_cm IS NOT NULL AND product_height_cm>0
                AND product_width_cm IS NOT NULL AND product_width_cm>0
                THEN 'Complete metadata'
            ELSE 'Partial metadata'
        END AS c_metadata_status
        FROM bronze.pim_products
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            5. silver.pim_product_category_name_translation
            -----------------------------------------------------------------------------
            Grain   : one row per product_category_name
            Sources : bronze.pim_product_category_name_translation
                        + category names used by products but absent from the translation

            Aspects applied:
                [Integration & enrichment]/[Referential integrity] Categories used by silver.pim_products that have NO translation
                                                                   are appended with a NULL english name, so every product category
                                                                   exists in the lookup (parent) table.
                                                   [NULL handling] NULL product_category_name (610 products) is NOT added: NULL NOT IN (..)
                                                                   evaluates to UNKNOWN, so those rows are excluded - which is wanted.
                                             [Duplicate handling]  UNION (not UNION ALL) removes exact duplicate rows.
                                                [Standardisation]  TRIM() on both name columns.

            Checks : section E  (and D3 for the products -> translation relationship)
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.pim_product_category_name_translation'
        PRINT '----------------------------------------------------';

        -- Loading silver.pim_product_category_name_translation
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.pim_product_category_name_translation';
        IF OBJECT_ID('silver.pim_product_category_name_translation', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.pim_product_category_name_translation;
        PRINT '>> Inserting Data Into: silver.pim_product_category_name_translation';
        INSERT INTO silver.pim_product_category_name_translation(
            product_category_name,
            product_category_name_english)

        SELECT 
        TRIM(product_category_name) AS product_category_name,
        ISNULL(TRIM(product_category_name_english), 'No english translation') AS product_category_name_english
        FROM (
            -- (a) translation table as delivered
            SELECT 
            TRIM(product_category_name) AS product_category_name,
            TRIM(product_category_name_english) AS product_category_name_english
            FROM bronze.pim_product_category_name_translation 
            UNION 
            -- (b) categories used by products but missing from the translation table
            SELECT 
            product_category_name, 
            NULL AS product_category_name_english
            FROM silver.pim_products 
            WHERE product_category_name NOT IN
                (SELECT TRIM(product_category_name) 
                FROM bronze.pim_product_category_name_translation
                WHERE TRIM(product_category_name) IS NOT NULL)
            )t
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            6. silver.ecom_orders
            -----------------------------------------------------------------------------
            Grain   : one row per order_id (also unique per customer_id)
            Source  : bronze.ecom_orders

            Aspects applied:
            [NULL handling][Business-rule validation] The Expected life cycle of an order status is as such: 
                                                        created -> approved -> invoiced -> processing -> shipped -> delivered
                                                        (plus the exits: canceled, unavailable)
                                                        Each of these statuses have should have NULLS as such:

                                                        status                 approved_at  carrier_date  customer_date   meaning of the NULLs
                                                        -----------            -----------  ------------  -------------   ---------------------
                                                        created                NULL         NULL          NULL            just created
                                                        approved               value        NULL          NULL            not shipped yet
                                                        invoiced               value        NULL          NULL            invoice before shipping
                                                        processing             value        NULL          NULL            being prepared
                                                        shipped                value        value         NULL            with courier
                                                        delivered              value        value         value           complete
                                                        unavailable            value        NULL          NULL            seller stops order after it is created and approved
                                                        canceled_pattern 1     value        value         NULL            (cancelled after delivery to courier before delivery to customers)
                                                        canceled_pattern 2     value        NULL          NULL            (cancelled after approval before delivery to courier)
                                                        canceled_pattern 3     NULL         NULL         NULL             (cancelled before approval)

                                                        So these NULLs are "not applicable YET" (process not reached), not errors.
                                                        They only become errors if NULLS exists for 'delivered' because every step must have happened.

                            [Date & timestamp validity]  c_date_order_validity : 'Invalid' if ANY earlier step is dated AFTER
                                                         a later step (purchase > approved > carrier >customer delivery).
                                         [NULL handling] c_delivery_timestamp_completeness : 'Incomplete' only for 'delivered'
                                                         orders missing a timestamp.
                             [Integration & enrichment]  c_overall_data_quality   : 'Good' only if both flags are clean, else 'Bad'.
                                      [Standardisation]  TRIM() on order_status.

            Review notes
                [i] SCOPE OF EXCLUSION IN GOLD. Exclude 'Bad' mixes orders with wrong DELIVERY
                    timestamps  DELIVERY-TIME/ LEAD-TIME metrics only, and keep them for REVENUE
                    metrics as they are still valid

            Checks : section F
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.ecom_orders'
        PRINT '----------------------------------------------------';

        -- Loading silver.ecom_orders
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.ecom_orders';
        IF OBJECT_ID('silver.ecom_orders', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.ecom_orders;
        PRINT '>> Inserting Data Into: silver.ecom_orders';
        INSERT INTO silver.ecom_orders(
            order_id,
            customer_id,
            order_status,
            order_purchase_timestamp,
            order_approved_at,
            order_delivered_carrier_date,
            order_delivered_customer_date,
            order_estimated_delivery_date,
            c_delivery_timestamp_validity,
            c_canceled_order_validity,
            c_date_order_validity,
            c_order_item_validity,
            c_order_payment_validity,
            c_order_rapid_check,
            c_overall_data_quality)

        SELECT 
        order_id,
        customer_id,
        TRIM(order_status) AS order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        c_delivery_timestamp_validity,
        c_canceled_order_validity,
        c_date_order_validity,
        c_order_item_validity,
        c_order_payment_validity,
        c_order_rapid_check,
        -- Overall flag combining both flags below   [Integration & enrichment]
        CASE WHEN (c_delivery_timestamp_validity ='Valid' 
                    AND c_date_order_validity = 'Valid'
                    AND c_canceled_order_validity = 'Valid'
                    AND c_order_item_validity = 'Valid'
                    AND c_order_payment_validity = 'Valid'
                    AND c_order_rapid_check = 'Not rapid')
            THEN 'Good'
            ELSE 'Bad'
        END AS c_overall_data_quality
        FROM ( SELECT *,
                -- Flag 1: delivered orders must have all three timestamps   [NULL handling][Business-rule validation]
                CASE WHEN TRIM(order_status) ='delivered' AND (order_approved_at IS NULL
                                                            OR order_delivered_carrier_date IS NULL
                                                            OR order_delivered_customer_date IS NULL)
                    THEN 'Invalid'
                    ELSE 'Valid'
                END AS c_delivery_timestamp_validity,
                -- Flag 2: cancelled orders must follow correct NULL rules [NULL handling][Business-rule validation]
                CASE WHEN TRIM(order_status) = 'canceled' AND (
	                                                            (order_approved_at IS NULL 
	                                                            AND	order_delivered_carrier_date IS NOT NULL
	                                                            AND order_delivered_customer_date IS NOT NULL)
                                                            OR (order_approved_at IS NULL 
	                                                            AND	order_delivered_carrier_date IS NULL
	                                                            AND order_delivered_customer_date IS NOT NULL)
                                                            OR (order_approved_at IS NULL 
	                                                            AND	order_delivered_carrier_date IS NOT NULL
	                                                            AND order_delivered_customer_date IS NULL)
                                                            OR (order_approved_at IS NOT NULL 
	                                                            AND	order_delivered_carrier_date IS NULL
	                                                            AND order_delivered_customer_date IS NOT NULL)
                                                            OR (order_approved_at IS NOT NULL 
	                                                            AND	order_delivered_carrier_date IS NOT NULL
	                                                            AND order_delivered_customer_date IS NOT NULL)
	                                                            )
                    THEN 'Invalid'
                    ELSE 'Valid'
                END AS c_canceled_order_validity,
                -- Flag 3: timestamps must follow chronological order   [Date & timestamp validity]
                CASE WHEN (order_purchase_timestamp > order_approved_at
                        OR order_purchase_timestamp > order_delivered_carrier_date
                        OR order_purchase_timestamp > order_delivered_customer_date
                        OR order_approved_at > order_delivered_carrier_date
                        OR order_approved_at > order_delivered_customer_date
                        OR order_delivered_carrier_date> order_delivered_customer_date)
                    THEN 'Invalid'
                    ELSE 'Valid'
                END AS c_date_order_validity,
                -- Flag 4: Orders with no order items must belong to valid order status [Business-rule validation]
                CASE WHEN order_id IN(SELECT o.order_id
						                FROM bronze.ecom_orders o
						                WHERE NOT EXISTS (SELECT 1 FROM bronze.ecom_order_items i
											            WHERE o.order_id = i.order_id)
						                AND o.order_status NOT IN ('canceled', 'unavailable', 'created', 'invoiced')
						        )
                    THEN 'Invalid'
                    ElSE 'Valid'
                END AS c_order_item_validity,
                -- Flag 5: Orders with no payments must belong to valid order status [Business-rule validation]
                CASE WHEN order_id IN (SELECT o.order_id
                                        FROM bronze.ecom_orders o
                                        WHERE NOT EXISTS (SELECT 1 FROM bronze.ecom_order_payments p
					                                        WHERE o.order_id = p.order_id)
                                        AND o.order_status NOT IN ('canceled', 'unavailable', 'created')
                                        )
                    THEN 'Invalid'
                    ElSE 'Valid'
                END AS c_order_payment_validity,
                -- Flag 6: Rapid repeat orders made by the same customer_unique_id <=60 seconds apart are categorised as such [Business-rule validation]
                CASE WHEN difference_previous <60 AND previous_purchase IS NOT NULL
	                    OR difference_next <60 AND next_purchase IS NOT NULL
	                THEN 'Rapid'
	                ELSE 'Not rapid'
                END AS c_order_rapid_check
                FROM (SELECT 
	                o.order_id,
	                o.customer_id,
                    o.order_status,
	                o.order_purchase_timestamp,
	                o.order_approved_at,
	                o.order_delivered_carrier_date,
	                o.order_delivered_customer_date,
	                o.order_estimated_delivery_date,
	                LAG(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS previous_purchase,
	                LEAD(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS next_purchase,
	                ABS(DATEDIFF(SECOND, o.order_purchase_timestamp, LAG(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp))) AS difference_previous,
	                ABS(DATEDIFF(SECOND, o.order_purchase_timestamp, LEAD(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp))) AS difference_next
	                FROM bronze.ecom_orders o 
	                LEFT JOIN silver.ecom_customers c
	                ON o.customer_id = c.customer_id
		                )f
                    )t
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            7. silver.ecom_order_items
            -----------------------------------------------------------------------------
            Grain   : one row per (order_id, order_item_id)  -> composite business key
            Source  : bronze.ecom_order_items  (straight copy, no cleaning needed so far)

            Aspects
                   [Referential integrity]  order_id -> ecom_orders, product_id -> pim_products,
                                            seller_id -> slm_sellers   (verified in checking file, section G)
                [Business-rule validation]  Items per order are numbered 1..N; shipping_limit_date depends on
                                            order + seller only (verified in section G).
                     [Data types & formats] price / freight_value should be numeric (DECIMAL) - confirm in DDL.

            Review notes
                [i] Orders WITHOUT items are normal for canceled / unavailable / created /
                    invoiced orders (see checking file F8). They are kept in silver. 
                    Revenue-type metrics in gold must be built from order_items, not orders.
                [i] Same product repeated in one order appears as separate order_item_id
                    rows (quantity > 1). That is a valid business pattern, not a duplicate.
         
            Checks : section G
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.ecom_order_items'
        PRINT '----------------------------------------------------';

        -- Loading silver.ecom_order_items
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.ecom_order_items';
        IF OBJECT_ID('silver.ecom_order_items', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.ecom_order_items;
        PRINT '>> Inserting Data Into: silver.ecom_order_items';
        INSERT INTO silver.ecom_order_items(
            order_id,
            order_item_id,
            product_id,
            seller_id,
            shipping_limit_date,
            price,
            freight_value)

        SELECT 
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
        FROM bronze.ecom_order_items
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            8. silver.ecom_order_payments
            -----------------------------------------------------------------------------
            Grain   : one row per (order_id, payment_sequential)
            Source  : bronze.ecom_order_payments

            Aspects applied
                 [Erroneous data]  payment_installments = 0 is impossible (a payment has >= 1 instalment),
                                   so 0 is set to 1.
                [Standardisation]  TRIM() on payment_type.

            Review notes
                [i] One order exists in orders but has NO payment row
                    (check file F9). 

            Checks : section H
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.ecom_order_payments'
        PRINT '----------------------------------------------------';

        -- Loading silver.ecom_order_payments
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.ecom_order_payments';
        IF OBJECT_ID('silver.ecom_order_payments', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.ecom_order_payments;
        PRINT '>> Inserting Data Into: silver.ecom_order_payments';
        INSERT INTO silver.ecom_order_payments(
            order_id,
            payment_sequential,
            payment_type,
            payment_installments,
            payment_value)

        SELECT 
        order_id,
        payment_sequential,
        TRIM(payment_type) AS payment_type,
        -- 0 instalments is impossible -> treat as a single payment   [Erroneous data]
        CASE WHEN payment_installments = 0 THEN 1
            ELSE payment_installments
        END AS payment_installments,
        payment_value
        FROM bronze.ecom_order_payments
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';


        /* =============================================================================
            9. silver.ecom_order_reviews
            -----------------------------------------------------------------------------
            Grain   : one row per review_id  (after de-duplication)
            Source  : bronze.ecom_order_reviews  LEFT JOIN  silver.ecom_orders

            Aspects applied
                [Duplicate handling]  Business-key duplicates (review_id) resolved by keeping the row tied
                                      to the customer's MOST RECENT order (ORDER BY purchase timestamp DESC).
                   [Standardisation]  TRIM() & NULLIF on title and message to convert empty strings into NULL

            Review notes
                [i] A customer can write many reviews; a review_id belongs to ONE customer.
                [i] 789 review_ids appear more than once (1,603 rows in total), i.e. the same
                    review_id is attached to several order_ids of the same customer.
                [i] 10 identical review "records" (score/title/comment/dates) exist under
                    different review_ids. They have no title and no comment, so it is a
                    coincidence between different customers, NOT an error. They are kept.
                [i] A review record never belongs to several order_ids.

            Checks : section I
            ============================================================================= */
        PRINT '----------------------------------------------------';
        PRINT 'Loading silver.ecom_order_reviews'
        PRINT '----------------------------------------------------';

        -- Loading silver.ecom_order_reviews
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.ecom_order_reviews';
        IF OBJECT_ID('silver.ecom_order_reviews', 'U') IS NOT NULL
	        TRUNCATE TABLE silver.ecom_order_reviews;
        PRINT '>> Inserting Data Into: silver.ecom_order_reviews';
        INSERT INTO silver.ecom_order_reviews(
            review_id,
            order_id,
            review_score,
            review_comment_title,
            review_comment_message,
            review_creation_date,
            review_answer_timestamp,
            c_is_primary_review)

        SELECT 
        review_id,
        order_id,
        review_score,
        NULLIF(TRIM(review_comment_title),'') AS review_comment_title,
        NULLIF(TRIM(review_comment_message),'') AS review_comment_message,
        review_creation_date,
        review_answer_timestamp,
        -- flag: assign most recent review by purchase timestamp as the primary review  [Duplication handling][Business rules]
        CASE WHEN flag = 1
            THEN 'Primary review'
            ELSE 'Secondary review'
        END AS c_is_primary_review
        FROM (SELECT r.review_id,
			        r.order_id,
			        r.review_score,
			        r.review_comment_title,
			        r.review_comment_message,
			        r.review_creation_date,
			        r.review_answer_timestamp,
			        -- Rank duplicates of the same review_id, newest order first   [Duplication handling]
			        ROW_NUMBER() OVER (PARTITION BY r.review_id ORDER BY o.order_purchase_timestamp DESC, r.order_id) AS flag
			        FROM bronze.ecom_order_reviews r
			        LEFT JOIN silver.ecom_orders o 
			        ON r.order_id = o.order_id
        )t 
        ;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + 'seconds';
        PRINT '>> --------------';

        SET @batch_end_time = GETDATE();
        PRINT '==========================================================';
        PRINT 'Loading Silver Layer is Completed';
        PRINT '     - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '==========================================================';

    END TRY
    BEGIN CATCH 
        PRINT '==========================================================';
        PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER';
        PRINT 'Error MEssage' + ERROR_MESSAGE();
        PRINT 'Error Message' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error Message' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '==========================================================';
    END CATCH
END
