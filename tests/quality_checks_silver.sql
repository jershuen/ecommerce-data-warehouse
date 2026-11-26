/* 
=============================================================================
 SILVER LAYER CHECKS   (run AFTER EXCE silver.load_silver
 =============================================================================
Script Purpose:
  This srcipt performs various quality checks for data consistency, accuracy 
  and standardisation across the Silver schemas. Checks are done for done for these:

   ASPECT TAGS
     [NULL] NULL handling              [DUP]  Duplicate handling
     [ERR]  Erroneous data             [TYPE] Data types & formats
     [DATE] Date/timestamp validity    [REF]  Referential integrity
     [BIZ]  Business rules             [STD]  Standardisation (TRIM, labels, units)
     [ENR]  Integration & enrichment

Usage Notes:
  - Run these checks ater data loading Silver layer.
  - Investigate and resolve any discrepancies found during the checks.

 How to read a check:
   <ID> | <aspect tags> <what is checked>
   Expectation : what a healthy table returns
   Result      : what you actually found (only where you recorded it)
   Verdict     : decision taken (keep / flag / exclude in gold / fix)
   Status tags : [i] information


 Table of contents:
   A. slm_geolocation                 F. ecom_orders
   B. ecom_customers                  G. ecom_order_items
   C. slm_sellers                     H. ecom_order_payments
   D. pim_products                    I. ecom_order_reviews
   E. pim_product_category_name_translation
 ============================================================================= */



--====================================
-- A. Checking for silver.slm_geolocation
--    Grain: one row per zip prefix
--====================================

-- A1 | [DUP][NULL] Primary key geolocation_zip_code_prefix is unique and not NULL
-- Expectation: No results
SELECT
geolocation_zip_code_prefix, count(*)
FROM silver.slm_geolocation
GROUP BY geolocation_zip_code_prefix
HAVING count(*)>1 OR geolocation_zip_code_prefix IS NULL
;

--A2 | [NULL] NULLS in any column
-- Expectation: No results
SELECT *
FROM silver.slm_geolocation
WHERE 
c_geo_source ='reference' AND (
geolocation_zip_code_prefix IS NULL
OR geolocation_lat IS NULL
OR geolocation_lng IS NULL
OR geolocation_city IS NULL
OR geolocation_state IS NULL)
;

-- A3 | [ERR] Coordinates are valid degrees (latitude -90 to +90, longitude -180 to +180)
-- Expectation: No results
SELECT geolocation_lat, geolocation_lng
FROM silver.slm_geolocation
WHERE ABS(geolocation_lat) >90 
	OR ABS(geolocation_lng) > 180 
;

-- A4 | [DUP][ERR] Number of distinct CITIES per zip (should be exactly one)
-- Expectation: No results
SELECT geolocation_zip_code_prefix, COUNT(DISTINCT geolocation_city) as city_distinct_count
FROM silver.slm_geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_city) >1
;

-- A5 | [DUP][ERR] Number of distinct STATES per zip (should be exactly one)
-- Expectation: No results
SELECT geolocation_zip_code_prefix, COUNT(DISTINCT geolocation_state) as state_distinct_count
FROM silver.slm_geolocation
GROUP BY geolocation_zip_code_prefix
HAVING COUNT(DISTINCT geolocation_state) >1
;
    
-- A6 | [STD] Cardinality of geolocation_state (no spelling / case variants)
-- Expectation: Visual inspection - one value per real state, no duplicates
SELECT DISTINCT geolocation_state
FROM silver.slm_geolocation 
;


--====================================
-- B. Checking for silver.ecom_customers
--    Grain: one row per customer_id (= one order); customer_unique_id = the person
--====================================

-- B1 | [DUP] Primary key customer_id is unique
-- Expectation: No results
SELECT customer_id, COUNT(*) 
FROM silver.ecom_customers
GROUP BY customer_id 
HAVING COUNT(*)>1 
;

-- B2 | [DUP] customer_unique_id repeats (repeat customers)
-- Expectation: (2997 rows). Duplicates present because they represent orders a customer makes
-- Verdict: valid business pattern - retain. This is the key RFM identifier.
SELECT 
customer_unique_id, COUNT(*) as number_of_orders
FROM silver.ecom_customers
GROUP BY customer_unique_id 
HAVING COUNT(*)>1
ORDER BY number_of_orders DESC
;

-- B3 | [REF] Every customer has at least one order
-- Expectation: No Results
SELECT c.*
FROM silver.ecom_customers c
WHERE NOT EXISTS (
	SELECT 1 FROM silver.ecom_orders o
	WHERE c.customer_id=o.customer_id)
;

-- B4 | [NULL] No NULLs in any column
-- Expectation: No Results
SELECT *
FROM silver.ecom_customers
WHERE customer_id IS NULL
	OR customer_unique_ID IS NULL
	OR customer_zip_code_prefix IS NULL
	OR customer_city IS NULL
	OR customer_state IS NULL
;

-- B5 | [REF] Customer zip exists in the geolocation reference
-- Expectation: no results
SELECT * 
FROM silver.ecom_customers 
WHERE customer_zip_code_prefix NOT IN(
	SELECT geolocation_zip_code_prefix 
	FROM silver.slm_geolocation)
;

-- B6 | [ENR][STD][ERR] Customer city matches reference city for the same zip
-- Expectation: No Results
SELECT 
	c.customer_zip_code_prefix,
	c.customer_city,
	g.geolocation_city
FROM silver.ecom_customers c
	LEFT OUTER JOIN silver.slm_geolocation g
	on c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
	where 
		g.geolocation_zip_code_prefix IS NULL
		OR c.customer_city IS NULL
		OR g.geolocation_city IS NULL
		OR c.customer_city != g.geolocation_city
;

-- B7 | [ENR][STD][ERR] Customer state matches reference state for the same zip
-- Expectation: No Results
SELECT 
	c.customer_zip_code_prefix, 
	c.customer_state,
	g.geolocation_state
FROM silver.ecom_customers c
	LEFT OUTER JOIN silver.slm_geolocation g
	on c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
	where 
		g.geolocation_zip_code_prefix IS NULL
		OR c.customer_state IS NULL
		OR g.geolocation_state IS NULL
		OR c.customer_state != g.geolocation_state
;


--====================================
-- C. Checking for silver.slm_sellers
--    Grain: one row per seller_id
--====================================

-- C1 | [DUP][NULL] Primary key seller_id is unique and not NULL
-- Expectation: No Results
SELECT
seller_id, count(*)
FROM silver.slm_sellers
GROUP BY seller_id
HAVING count(*)>1 OR seller_id IS NULL
;

-- C2 | [NULL] No NULLs in any column
-- Expectation: No Results
SELECT *
FROM silver.slm_sellers
WHERE seller_id IS NULL
	OR seller_zip_code_prefix IS NULL
	OR seller_city IS NULL
	OR seller_state IS NULL
;

-- C3 | [REF] Seller zip exists in the geolocation reference
-- Expectation: no results
SELECT * 
FROM silver.slm_sellers
WHERE seller_zip_code_prefix NOT IN(
	SELECT geolocation_zip_code_prefix 
	FROM silver.slm_geolocation)
;

-- C4 | [ENR][STD][ERR] Seller city matches reference city for the same zip
-- Expectation: No Results
SELECT 
	s.seller_zip_code_prefix,
	s.seller_city,
	g.geolocation_city
FROM silver.slm_sellers s
	LEFT OUTER JOIN silver.slm_geolocation g
	on s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
	where 
		g.geolocation_zip_code_prefix IS NULL
		OR s.seller_city IS NULL
		OR g.geolocation_city IS NULL
		OR s.seller_city != g.geolocation_city
;

-- C5 | [ENR][STD][ERR] Seller state matches reference state for the same zip
-- Expectation: No Results
SELECT 
	s.seller_zip_code_prefix, 
	s.seller_state,
	g.geolocation_state
FROM silver.slm_sellers s
	LEFT OUTER JOIN silver.slm_geolocation g
	on s.seller_zip_code_prefix = g.geolocation_zip_code_prefix
	where 
		g.geolocation_zip_code_prefix IS NULL
		OR s.seller_state IS NULL
		OR g.geolocation_state IS NULL
		OR s.seller_state != g.geolocation_state
;



--====================================
-- D. Checking for silver.pim_products
--    Grain: one row per product_id
--====================================

-- D1 | [DUP][NULL] Primary key product_id is unique and not NULL
-- Expectation: No Results
SELECT product_id, COUNT(*)
FROM silver.pim_products
GROUP BY product_id 
HAVING COUNT(*)>1 OR product_id IS NULL
;

-- D2 | [NULL] NULLs in any column
-- Expectation (ideal): No Results
-- Result: 611 rows contain NULLs (genuinely missing, not "not applicable"):
--   - 609 rows: NULL in descriptive attributes (category name, name length,
--               description length, photo quantity), physical dimensions present
--   -   1 row : NULL in physical dimensions (weight, length, height, width),
--               descriptive attributes present
--   -   1 row : NULL in BOTH (product_id = '5eb564652db742ff8f28759cd8d2652a')
-- Verdict: cannot remove them (they are real products that were sold) and there
--          is no evidence to impute values. Kept and labelled via c_metadata_status.
SELECT *
FROM silver.pim_products
WHERE product_id IS NULL
OR product_category_name IS NULL
OR product_name_length IS NULL
OR product_description_length IS NULL
OR product_photos_qty IS NULL
OR product_weight_g IS NULL
OR product_length_cm IS NULL
OR product_height_cm IS NULL
OR product_width_cm IS NULL
;

-- D3 | [ERR] Suspicious product measures and item prices
-- Expectation: No results (or a small, explainable list)
SELECT product_id, product_weight_g, product_length_cm, product_height_cm, product_width_cm, product_photos_qty
FROM silver.pim_products
WHERE product_weight_g <= 0 OR product_length_cm <= 0 OR product_height_cm <= 0
   OR product_width_cm <= 0 OR product_photos_qty < 0
;

-- D4 | [REF] Product category exists in the translation (parent) table
-- Expectation (after transformation): ONLY the NULL category (610 products)
-- Result (BEFORE the missing categories were appended): 2 categories had no
--   english translation, and 610 products had no category name.
-- Verdict: the 2 categories are now appended to the translation table by the
--   transformation; they still need a manual english translation (see E2).
SELECT product_category_name, COUNT(*) 
FROM silver.pim_products
WHERE product_category_name NOT IN
(SELECT product_category_name
FROM silver.pim_product_category_name_translation)
OR product_category_name IS NULL
GROUP BY product_category_name
;


--===========================================================
-- E. Checking for silver.pim_product_category_name_translation
--    Grain: one row per product_category_name
--===========================================================

-- E1 | [DUP][NULL] Primary key product_category_name is unique and not NULL
-- Expectation: No Results
SELECT product_category_name, COUNT(*)
FROM silver.pim_product_category_name_translation
GROUP BY product_category_name 
HAVING COUNT(*)>1 OR product_category_name IS NULL
;

-- E2 | [NULL] No NULLs in any column
-- Expectation: No Results
SELECT *
FROM silver.pim_product_category_name_translation
WHERE product_category_name IS NULL
OR product_category_name_english IS NULL
;


-- E3 | [STD] Unwanted spaces in names
-- Expectation: No Results
SELECT *
FROM silver.pim_product_category_name_translation
WHERE DATALENGTH(product_category_name) != DATALENGTH(TRIM(product_category_name))
OR DATALENGTH(product_category_name_english) != DATALENGTH(TRIM(product_category_name_english))
;


--===========================================================
-- F. Checking for silver.ecom_orders
--    Grain: one row per order_id
--===========================================================

-- F1 | [REF] Every order's customer_id exists in customers (parent)
-- Expectation: No Results
SELECT *
FROM silver.ecom_orders
WHERE customer_id NOT IN (SELECT customer_id FROM silver.ecom_customers)
;

-- F2 | [DUP][NULL] Primary key order_id is unique and not NULL
-- Expectation: No Results
SELECT order_id, COUNT(*)
FROM silver.ecom_orders
GROUP BY order_id 
HAVING COUNT(*)>1 OR order_id IS NULL
;

-- F3 | [DUP][NULL] customer_id is unique per order
-- Expectation: No Results
-- [i] customer_id is generated PER ORDER. Repeat buyers show up as the same
--     customer_UNIQUE_id with different customer_ids (see B2, R8).
SELECT customer_id, COUNT(*)
FROM silver.ecom_orders
GROUP BY customer_id 
HAVING COUNT(*)>1 OR customer_id IS NULL
;

-- F4 | [STD] Cardinality of order_status (no spelling / case / space variants)
-- Expectation: Shows no need for correction
-- Valid statuses: created, approved, invoiced, processing, shipped, delivered,
--                 canceled, unavailable
SELECT DISTINCT order_status
FROM silver.ecom_orders
;

-- F5 | [NULL][BIZ] Validating NULLs against the order lifecycle
-- NULLs only exist in three columns: order_approved_at, order_delivered_carrier_date
-- and order_delivered_customer_date. A NULL is NORMAL if the process step has not
-- been reached yet, and an ERROR if the status says it was.
--
--   status       approved_at  carrier_date  customer_date
--   created      NULL         NULL          NULL
--   approved     value        NULL          NULL
--   invoiced     value        NULL          NULL
--   processing   value        NULL          NULL
--   shipped      value        value         NULL
--   delivered    value        value         value
--   canceled     any, as long as a later date never exists without an earlier one
--   unavailable  value        NULL          NULL   (hypothesis, see R2)

-- F5.1 | If status = 'created': all three are NULL
-- Expectation: No result
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'created'
AND NOT(order_approved_at IS NULL	
		AND order_delivered_carrier_date IS NULL
		AND order_delivered_customer_date IS NULL)
;

-- F5.2 | If status = 'approved': only carrier and customer dates are NULL
-- Expectation: No result
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'approved' 
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NULL
		AND order_delivered_customer_date IS NULL)
;

-- F5.3 | If status = 'invoiced': only carrier and customer dates are NULL
-- Expectation: No result
-- [i] Supports the hypothesis that invoicing happens BEFORE shipping/delivery.
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'invoiced'
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NULL
		AND order_delivered_customer_date IS NULL)
;

-- F5.4 | If status = 'processing': only carrier and customer dates are NULL
-- Expectation: No result
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'processing'
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NULL
		AND order_delivered_customer_date IS NULL)
;

-- F5.5 | If status = 'shipped': only the customer delivery date is NULL
-- Expectation: No results
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'shipped'
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NOT NULL
		AND order_delivered_customer_date IS NULL)
;

-- F5.6 | If status = 'delivered': there should be NO NULLs
-- Expectation: No results
-- Result: 23 rows with NULLs in at least one of the three columns. Broken down below.
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'delivered'
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NOT NULL
		AND order_delivered_customer_date IS NOT NULL)
;

-- F5.6.1 | Delivered orders have an approval date
-- Expectation: No results
-- Result: 14 rows are delivered without approval.
-- Verdict: exclude from gold (c_delivery_timestamp_validity = 'Invalid').
SELECT * 
FROM silver.ecom_orders 
WHERE order_status ='delivered'
AND order_approved_at IS NULL
;

-- F5.6.2 | Delivered orders have a carrier handover date
-- Expectation: No results
-- Result: 2 rows are delivered without a carrier handover date.
-- Verdict: exclude from gold (c_delivery_timestamp_validity = 'Invalid').
SELECT * 
FROM silver.ecom_orders 
WHERE order_status ='delivered'
AND order_delivered_carrier_date IS NULL
;

-- F5.6.3 | Delivered orders have a customer delivery date
-- Expectation: No results
-- Result: 8 rows are delivered without a delivery date.
-- Verdict: exclude from gold (c_delivery_timestamp_validity = 'Invalid').
SELECT * 
FROM silver.ecom_orders 
WHERE order_status ='delivered'
AND order_delivered_customer_date IS NULL
;

-- F5.7 | Canceled orders follow a valid NULL sequence. Allowed patterns
--        (approval date, carrier handover date, customer delivery date):
	-- NOT NULL, NOT NULL, NULL
	-- NOT NULL, NULL, NULL
	-- NULL, NULL, NULL
-- The query lists the 5 forbidden patterns (a later date without an earlier one).
-- Expectation: No result
-- Verdict: exclude from gold (c_canceled_order_validity = 'Invalid').

SELECT *
FROM silver.ecom_orders
WHERE order_status = 'canceled'
AND (
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
;

-- F5.8 | If status = 'unavailable': only carrier and customer dates are NULL
-- Expectation: No result
SELECT *
FROM silver.ecom_orders
WHERE order_status = 'unavailable'
AND NOT(order_approved_at IS NOT NULL	
		AND order_delivered_carrier_date IS NULL
		AND order_delivered_customer_date IS NULL)
;

-- F6 | [DATE][ERR] Implausible dates (before 1900 or after 2050)
-- Expectation: No result
SELECT * 
FROM silver.ecom_orders
WHERE (order_purchase_timestamp> '2050-01-01'
		OR order_purchase_timestamp < '1900-01-01')
	OR (order_approved_at> '2050-01-01'
		OR order_approved_at < '1900-01-01')
	OR (order_delivered_carrier_date> '2050-01-01'
		OR order_delivered_carrier_date < '1900-01-01')
	OR (order_delivered_customer_date> '2050-01-01'
		OR order_delivered_customer_date < '1900-01-01')
	OR (order_estimated_delivery_date> '2050-01-01'
		OR order_estimated_delivery_date < '1900-01-01')
;

-- F7 | [DATE] Chronological order: purchase <= approval <= carrier <= delivery
-- Each query lists rows where an EARLIER step is dated AFTER a LATER one.
-- Verdicts below are implemented by the flag c_date_order_validity = 'Invalid'.


-- F7.1 | Purchase date <= approval date
-- Expectation: No result
SELECT * 
FROM silver.ecom_orders
WHERE (order_purchase_timestamp > order_approved_at) 
;

-- F7.2 | Purchase date <= carrier date
-- Expectation: No result
-- Result: 166 rows where the carrier received the order BEFORE it was purchased.
--   Mostly small hour/minute differences, but still impossible.
-- Verdict: exclude from delivery metrics in gold (c_date_order_validity = 'Invalid').
SELECT *
FROM silver.ecom_orders
WHERE (order_purchase_timestamp > order_delivered_carrier_date)
;

-- F7.3 | Purchase date <= customer delivery date
-- Expectation: No result
SELECT *
FROM silver.ecom_orders
WHERE (order_purchase_timestamp > order_delivered_customer_date) 
;

-- F7.4 | Approval date <= carrier date
-- Expectation: No result
-- Result: 1359 rows where the carrier received the order BEFORE it was approved.
-- Verdict: exclude from delivery metrics in gold (c_date_order_validity = 'Invalid').
SELECT *
FROM silver.ecom_orders
WHERE order_approved_at > order_delivered_carrier_date
;

-- F7.5 | Approval date <= customer delivery date
-- Expectation: No result
-- Result: 61 rows delivered to the customer BEFORE approval.
-- Verdict: exclude from delivery metrics in gold (c_date_order_validity = 'Invalid').
SELECT *
FROM silver.ecom_orders
WHERE (order_approved_at > order_delivered_customer_date)
;

-- F7.6 | Carrier date <= customer delivery date
-- Expectation: No result
-- Result: 23 rows delivered to the customer BEFORE handed to the carrier.
-- Verdict: exclude from delivery metrics in gold (c_date_order_validity = 'Invalid').
SELECT * 
FROM silver.ecom_orders
WHERE (order_delivered_carrier_date> order_delivered_customer_date)
;

-- F7.7 | Estimated delivery before purchase
-- Expectation: No results
SELECT * 
FROM silver.ecom_orders 
WHERE order_estimated_delivery_date < order_purchase_timestamp
;

-- F8 | [REF][BIZ] Orders with NO items are only those that are canceled, unavailable, created and invoiced. 
-- Expectation: No result
-- Result: 1 row with shipped order status has no items. 
-- Verdict: exclude from delivery metrics (c_order_item_validity ='Invalid')
SELECT *
FROM silver.ecom_orders o
WHERE NOT EXISTS (SELECT 1 FROM silver.ecom_order_items	i
					WHERE o.order_id = i.order_id)
AND o.order_status NOT IN ('canceled', 'unavailable', 'created', 'invoiced')

-- F9 | [REF][BIZ] Orders with NO payments are only those that are canceled, unavailable and created.  
-- Expectation: No results
-- Result: 1 row with delivered order status has no items. 
-- Verdict: exclude from delivery metrics (c_order_payment_validity ='Invalid')
SELECT *
FROM silver.ecom_orders o
WHERE NOT EXISTS (SELECT 1 FROM silver.ecom_order_payments p
					WHERE o.order_id = p.order_id)
AND o.order_status NOT IN ('canceled', 'unavailable', 'created')

--F10 | [BIZ] Rapid repeat orders: same customer_unique_id, <= 60 seconds apart
-- Expectations: No results
-- Results: there are 763 unique customers with rapid orders.
-- Verdict: exclude from delivery metrics (c_order_rapid_check ='Rapid')
SELECT customer_unique_id, COUNT(*) FROM(SELECT 
				o.order_id,
				c.customer_unique_id,
				o.order_purchase_timestamp,
				LAG(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS previous_purchase,
				LEAD(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) AS next_purchase,
				ABS(DATEDIFF(SECOND, o.order_purchase_timestamp, LAG(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp))) AS difference_previous,
				ABS(DATEDIFF(SECOND, o.order_purchase_timestamp, LEAD(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp))) AS difference_next,
				o.c_order_rapid_check
				FROM silver.ecom_orders o
				LEFT JOIN silver.ecom_customers c
				ON o.customer_id = c.customer_id
				)t
WHERE difference_previous <60 AND previous_purchase IS NOT NULL
OR difference_next <60 AND next_purchase IS NOT NULL
GROUP BY customer_unique_id



--===========================================================
-- G. Checking for silver.ecom_order_items
--    Grain: one row per (order_id, order_item_id)
--===========================================================

-- G1 | [REF] order_id exists in parent table ecom_orders
-- Expectation: no results
SELECT * 
FROM silver.ecom_order_items
WHERE order_id NOT IN(SELECT order_id FROM silver.ecom_orders)
;

-- G2 | [REF] seller_id exists in parent table slm_sellers
-- Expectation: no results
SELECT * 
FROM silver.ecom_order_items
WHERE seller_id NOT IN(SELECT seller_id FROM silver.slm_sellers)
;

-- G3 | [REF] product_id exists in parent table pim_products
-- Expectation: no results
SELECT * 
FROM silver.ecom_order_items
WHERE product_id NOT IN(SELECT product_id FROM silver.pim_products)
;

-- G4 | [NULL] No NULLs in any column
-- Expectation: No results
SELECT *
FROM silver.ecom_order_items
WHERE order_id IS NULL
OR product_id IS NULL
OR seller_id IS NULL
OR shipping_limit_date IS NULL
OR price IS NULL
OR freight_value IS NULL
;

-- G5 | [DUP][BIZ] Item numbering is complete: row count per order = highest order_item_id
-- Expectation: No results
SELECT order_id, 
COUNT(*) AS duplicate_orders,
MAX(order_item_id) AS max_order_items
FROM silver.ecom_order_items
GROUP BY order_id
HAVING COUNT(*) != MAX(order_item_id)
;

-- G6 | [DUP] Composite key (order_id, order_item_id) is unique
-- Expectation no results
SELECT 
order_id, 
order_item_id, 
COUNT(*) as duplicate_occurances
FROM silver.ecom_order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) >1
;

-- G7 | [DATE][ERR] shipping_limit_date is a plausible date
-- Expectation: No results
-- [?] Also compare with the order's purchase date (S6).
SELECT *
FROM silver.ecom_order_items
WHERE (shipping_limit_date > '2050-01-01'
		OR shipping_limit_date < '1900-01-01')
;

-- G8 | [DATE] Shipping limit date before the order was purchased
-- Expectation: No results
SELECT i.order_id, i.shipping_limit_date, o.order_purchase_timestamp
FROM silver.ecom_orders o 
LEFT JOIN silver.ecom_order_items i 
ON o.order_id = i.order_id
WHERE i.shipping_limit_date < o.order_purchase_timestamp
;

-- G9 | [ERR] price and freight_value are not negative (or NULL)
-- Expectation: No results
SELECT *
FROM silver.ecom_order_items
WHERE price <=0 
OR price IS NULL 
OR freight_value <0 
OR freight_value IS NULL
;

-- G9 | [BIZ][DATE] Within an order, #distinct shipping limit dates <= #distinct sellers
-- Rationale: shipping_limit_date depends only on the order date and the seller.
-- Expectation: No results
SELECT order_id, 
COUNT(DISTINCT shipping_limit_date) AS count_distinct_shipping_limit,
COUNT(DISTINCT seller_id) AS count_distinct_seller
FROM silver.ecom_order_items
GROUP BY order_id
HAVING COUNT(DISTINCT shipping_limit_date) > COUNT(DISTINCT seller_id) 
;


--===========================================================
-- H. Checking for silver.ecom_order_payments
--    Grain: one row per (order_id, payment_sequential)
--===========================================================

-- H1 | [REF] order_id exists in parent table ecom_orders
-- Expectation: no results
SELECT * 
FROM silver.ecom_order_payments
WHERE order_id NOT IN(SELECT order_id FROM silver.ecom_orders)
;

-- H2 | [DUP] Repeated order_id is explained by payment_sequential (key is unique)
-- Expectation: No results
SELECT order_id, payment_sequential, COUNT(*)
FROM silver.ecom_order_payments
GROUP BY order_id, payment_sequential 
HAVING COUNT(*) >1;

-- H3 | [NULL] No NULLs in any column
-- Expectation: No results
SELECT * 
FROM silver.ecom_order_payments
WHERE order_id IS NULL 
OR payment_sequential IS NULL
OR payment_type IS NULL
OR payment_installments IS NULL
OR payment_value IS NULL
;

-- H4 | [STD] Cardinality of payment_type (no spelling / case variants)
-- Expectation: Visual inspection
SELECT DISTINCT payment_type
FROM silver.ecom_order_payments
;

-- H5 | [ERR] Cardinality of payment_installments
-- Expectation: No 0 should appear (the transformation turns 0 into 1).
SELECT *
FROM bronze.ecom_order_payments
WHERE payment_installments <1
;


-- H6 | [ERR] Numbers are valid
-- Expectation: No results
SELECT * 
FROM silver.ecom_order_payments
WHERE payment_sequential <1 OR payment_sequential IS NULL
OR payment_installments <1 OR payment_installments IS NULL
OR payment_value <0 OR payment_value IS NULL
;

-- H7 | [BIZ] Instalments > 1 are only possible for credit cards
-- Expectation: No results (or explainable)
SELECT payment_type, payment_installments, COUNT(*) AS payments
FROM silver.ecom_order_payments
WHERE payment_installments > 1 AND payment_type != 'credit_card'
GROUP BY payment_type, payment_installments
;

-- H8 | [BIZ] Money reconciliation per order: payments vs items + freight
-- Differences can be legitimate (vouchers, rounding, interest on instalments);
-- tolerance of 1 currency unit is a starting point. Expect a SMALL list.




--===========================================================
-- I. Checking for silver.ecom_order_reviews
--    Grain: one row per review_id (after de-duplication in the transformation)
--===========================================================

-- I1 | [REF] order_id exists in parent table ecom_orders
-- Expectation: no results
SELECT * 
FROM silver.ecom_order_reviews
WHERE order_id NOT IN(SELECT order_id FROM silver.ecom_orders)
;

-- I2 | [DUP] review_id is unique
-- Expectation: No results
-- Results: 789 reviews with duplicates
-- Verdict: only primary reviews, calculated by most recent purchase timestamp is kept, the rest are excluded from gold (c_is_primary = 'Secondary').
SELECT review_id, COUNT(*)
FROM silver.ecom_order_reviews
GROUP BY review_id HAVING COUNT(*)>1
;

-- I3 | [NULL] No NULLs in key/required columns (title and message are optional)
-- Expectation: No results
SELECT *
FROM silver.ecom_order_reviews
WHERE review_id IS NULL
OR order_id IS NULL
OR review_score IS NULL
OR review_creation_date IS NULL
OR review_answer_timestamp IS NULL
;

-- I4 | [DATE][ERR] Review dates are plausible and creation <= answer
-- Expectation: No results
SELECT *
FROM silver.ecom_order_reviews
WHERE review_creation_date > review_answer_timestamp
OR (review_creation_date > '2050-01-01'
		OR review_creation_date < '1900-01-01')
OR (review_answer_timestamp > '2050-01-01'
		OR review_answer_timestamp < '1900-01-01')
;

-- I5 | [STD] There should be no empty tiles or messages; they all must be NULL
-- Expectation: No results
-- Results: 11 rows where title or message are empty string.
-- Verdict: convert them into NULL using 'NULLIF'
SELECT * FROM silver.ecom_order_reviews 
WHERE review_comment_title =''
OR review_comment_message =''
;

-- I6 [ERR] Review score outside 1-5
-- Expectation: No results
SELECT * FROM silver.ecom_order_reviews
WHERE review_score NOT BETWEEN 1 AND 5
;

-- I7 | [BIZ][REF] Each review_id is tied to exactly one customer_unique_id
-- Expectation: No results
SELECT 
r.review_id, 
COUNT(DISTINCT c.customer_unique_id) AS number_of_unique_customers
FROM silver.ecom_order_reviews r 
LEFT JOIN silver.ecom_orders o
	ON r.order_id = o.order_id
LEFT JOIN silver.ecom_customers c
	ON o.customer_id = c.customer_id
GROUP BY r.review_id
HAVING COUNT(DISTINCT c.customer_unique_id) !=1 
;

-- I8 | [BIZ] Duplicate reviews are made by the same customer
-- Expectation: no results
SELECT review_id, COUNT(DISTINCT customer_unique_id)
FROM silver.ecom_order_reviews r
LEFT JOIN silver.ecom_orders o
ON r.order_id = o.order_id
LEFT JOIN silver.ecom_customers c
ON o.customer_id = c.customer_id
GROUP BY review_id HAVING COUNT(DISTINCT customer_unique_id) >1
;

-- I9 | [DUP] The same order must not have multiple of the same review record
-- Expectation: no results
SELECT order_id, 
CONCAT(review_score, ',',
		review_comment_title, ',',
		review_comment_message, ',',
		review_creation_date, ',',
		CONVERT(VARCHAR(50), review_answer_timestamp, 120)) AS review_record,
COUNT(*) as duplicate_records
FROM silver.ecom_order_reviews
GROUP BY order_id, 
CONCAT(review_score, ',',
		review_comment_title, ',',
		review_comment_message, ',',
		review_creation_date, ',',
		CONVERT(VARCHAR(50), review_answer_timestamp, 120))
HAVING COUNT(*) >1
ORDER BY COUNT(*) DESC
;

-- I10 | [DUP][BIZ] Can one identical review record belong to several review_ids?  YES
-- Result: 10 review records have more than one distinct review_id.
-- Verdict: NOT an error. Two different customers can write the same score with no
--          title and no comment. Retained.
-- [i] CONCAT treats NULL as empty text, so 'no title / no comment' records match.
SELECT 
CONCAT(review_score, ',',
		review_comment_title, ',',
		review_comment_message, ',',
		review_creation_date, ',',
		CONVERT(VARCHAR(50), review_answer_timestamp, 120)) AS review_record,
COUNT(DISTINCT review_id)
FROM silver.ecom_order_reviews
GROUP BY CONCAT(review_score, ',',
		review_comment_title, ',',
		review_comment_message, ',',
		review_creation_date, ',',
		CONVERT(VARCHAR(50), review_answer_timestamp, 120))
HAVING COUNT(DISTINCT review_id)>1
ORDER BY COUNT(DISTINCT review_id) DESC
;

-- I11 | [DUP][BIZ] Do duplicated review_ids come from those rapid repeat orders?
-- Expectation: Only Rapid orders
-- Results: there are 124 orders that are not rapid, and 1479 rapid orders. 
-- Verdict: non-rapid orders with same reviews are very likely system errors and must be excluded in gold.
SELECT o.c_order_rapid_check, COUNT(*)
FROM bronze.ecom_order_reviews r
LEFT JOIN silver.ecom_orders o
ON o.order_id = r.order_id
WHERE r.review_id IN (SELECT review_id FROM bronze.ecom_order_reviews				
						GROUP BY review_id HAVING COUNT(*) >1)
GROUP BY o.c_order_rapid_check
;


