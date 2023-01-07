-- Atliq Hardware Financial Analysis

-- 1. Generate an Yearly Report for Croma India Having 2 Columns (Year, Total_Gross_Sales)

SELECT 
    GET_FISCAL_YEAR(s.date) AS Year,
    ROUND(SUM((s.sold_quantity * gp.gross_price)),
            2) AS Gross_Total_Sales
FROM
    fact_sales_monthly s
        JOIN
    fact_gross_price gp ON s.product_code = gp.product_code
        AND gp.fiscal_year = GET_FISCAL_YEAR(s.date)
WHERE
    s.customer_code = (SELECT 
            customer_code
        FROM
            dim_customer
        WHERE
            customer LIKE '%croma%')
GROUP BY 1
ORDER BY 1;

-- 2. Generate a Quarterly Sales Report for Croma India. 

SELECT 
    GET_FISCAL_YEAR(s.date) AS year,
	GET_FISCAL_QUARTER(s.date) AS QUARTER,
    ROUND(SUM((s.sold_quantity * gp.gross_price)),
            2) AS total_sales
FROM
    fact_sales_monthly s
        JOIN
    fact_gross_price gp ON s.product_code = gp.product_code
        AND gp.fiscal_year = GET_FISCAL_YEAR(s.date)
WHERE
    s.customer_code = (SELECT 
            customer_code
        FROM
            dim_customer
        WHERE
            customer LIKE '%croma%')
GROUP BY 1, 2
ORDER BY 1, 2;

-- 3. Generate a Monthly Sales Report for Croma India. 

SELECT
	s.fiscal_year,
    MONTH(s.date) as Month, 
    ROUND(SUM(gp.gross_price * s.sold_quantity), 2) as Total_Monthly_Sales
FROM
    fact_sales_monthly s
        JOIN
    fact_gross_price gp ON s.product_code = gp.product_code
        AND gp.fiscal_year = GET_FISCAL_YEAR(s.date)
WHERE
    s.customer_code = (SELECT 
            customer_code
        FROM
            dim_customer
        WHERE
            customer LIKE '%croma%')
GROUP BY s.fiscal_year, s.date
ORDER BY 1;


-- 4. Write a Query that can create a Market Badge based on following conditions. 

-- If sold quantities > 5 million -> Gold else -> Silver 

SELECT 
    c.market,
    CASE
        WHEN ROUND(SUM(s.sold_quantity) / 1000000) >= 5 THEN 'Gold'
        ELSE 'Silver'
    END AS Total_Quantities_Sold
FROM
    dim_customer c
        JOIN
    fact_sales_monthly s ON c.customer_code = s.customer_code
WHERE
    GET_FISCAL_YEAR(s.date) = 2018
GROUP BY 1
ORDER BY 1;

-- Sales Analytics

-- Create View for sales_preinv_discount, sales_postinv_discount, net_sales. 

-- View for sales_pre_invoic_disc
CREATE VIEW sales_preinv_discount AS
    SELECT 
        s.date,
        s.fiscal_year,
        s.customer_code,
        c.market,
        s.product_code,
        p.product,
        p.variant,
        s.sold_quantity,
        g.gross_price AS gross_price_per_item,
        ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
        pre.pre_invoice_discount_pct
    FROM
        fact_sales_monthly s
            JOIN
        dim_customer c ON s.customer_code = c.customer_code
            JOIN
        dim_product p ON s.product_code = p.product_code
            JOIN
        fact_gross_price g ON g.fiscal_year = s.fiscal_year
            AND g.product_code = s.product_code
            JOIN
        fact_pre_invoice_deductions AS pre ON pre.customer_code = s.customer_code
            AND pre.fiscal_year = s.fiscal_year;

-- View for sales_post_invoic_disc

CREATE VIEW sales_postinv_discount AS
	SELECT 
    	    s.date, s.fiscal_year,
            s.customer_code, s.market,
            s.product_code, s.product, s.variant,
            s.sold_quantity, s.gross_price_total,
            s.pre_invoice_discount_pct,
            (s.gross_price_total-s.pre_invoice_discount_pct*s.gross_price_total) as net_invoice_sales,
            (po.discounts_pct+po.other_deductions_pct) as post_invoice_discount_pct
	FROM sales_preinv_discount s
	JOIN fact_post_invoice_deductions po
		ON po.customer_code = s.customer_code AND
   		po.product_code = s.product_code AND
   		po.date = s.date;

-- View for net_sales

CREATE VIEW net_sales AS
	SELECT 
            *, 
    	    net_invoice_sales*(1-post_invoice_discount_pct) as net_sales
	FROM gdb041.sales_postinv_discount;
    



-- 1. Write a Query for generating Top 10 Markets.

SELECT 
    market,
    ROUND(SUM(net_sales) / 1000000, 2) AS total_net_sales
FROM
    net_sales
WHERE
    fiscal_year = 2018
GROUP BY market
ORDER BY 2 DESC
LIMIT 5;

-- 2. Write a Query for generating Top 10 Customers.

SELECT 
    customer,
    ROUND(SUM(net_sales) / 1000000, 2) AS total_net_sales
FROM
    net_sales s
        JOIN
    dim_customer c ON c.customer_code = s.customer_code
WHERE
    fiscal_year = 2021
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- 3. Write a Query for generating Top 10 Products.
SELECT 
    p.product,
    ROUND(SUM(net_sales) / 1000000, 2) AS total_net_sales
FROM
    net_sales s
        JOIN
    dim_product p ON p.product_code = s.product_code
WHERE
    fiscal_year = 2021
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- 4. Generate a Report by % net_sales for top 10 customers globally.

SELECT 
    c.customer, ROUND(SUM(s.net_sales), 2) / SUM(s.net_sales) OVER(ORDER BY s.net_sales) AS total_sales
FROM
    net_sales s
        JOIN
    dim_customer c ON c.customer_code = s.customer_code
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- 5. Generate a Report for region wise % net sales report for FY-21
WITH cte as (
SELECT 
    c.region,
    c.customer,
    ROUND(SUM(s.net_sales) / 1000000, 2) AS net_sales_mln
FROM
    net_sales s
        JOIN
    dim_customer c ON s.customer_code = c.customer_code
WHERE
    s.fiscal_year = 2021
GROUP BY 1, 2) 

SELECT 
	region, 
    customer, 
    ROUND((net_sales_mln * 100) / SUM(net_sales_mln) OVER(PARTITION BY region), 2) AS pct_net_sales
FROM 
	cte
ORDER BY 1, 3 DESC;

-- 6. Retrieve the top 2 markets in every region by their gross sales amount in FY=2021.

WITH cte as (
SELECT 
    c.market,
    c.region,
    ROUND(SUM(gp.gross_price * s.sold_quantity) / 1000000, 2) AS gross_total_price
FROM
    fact_sales_monthly s
        JOIN
    fact_gross_price gp ON s.fiscal_year = gp.fiscal_year
        AND gp.product_code = s.product_code
        JOIN
    dim_customer c ON s.customer_code = c.customer_code
    WHERE s.fiscal_year = 2021
    GROUP BY 1,2
    ORDER BY 3 desc),
cte2 AS (    
SELECT *,
		DENSE_RANK() OVER(PARTITION BY region ORDER BY gross_total_price DESC) as rnk
FROM cte)

SELECT 
    *
FROM
    cte2
WHERE
    rnk < 3;



-- Supply Chain Analytics. 

-- 1. Generate Forecast accuracy for all customers for a given fiscal year. 

WITH CTE AS (
SELECT 
    customer_code,
    SUM(sold_quantity) AS total_quantity_sold,
    SUM(forecast_quantity) AS total_forecast_quantity,
    SUM(ABS(sold_quantity - forecast_quantity)) AS abs_net_err,
    SUM(ABS(sold_quantity - forecast_quantity)) / SUM(forecast_quantity) AS abs_net_err_pct
FROM
    fact_act_est
WHERE
    fiscal_year = 2021
GROUP BY 1) 

SELECT 
    c.customer,
    c.market,
    c.region,
    f.total_quantity_sold,
    f.total_forecast_quantity,
    CASE
        WHEN abs_net_err_pct > 1 THEN 0
        ELSE (1 - abs_net_err_pct) * 100
    END AS forecast_accuracy
FROM
    cte f
        JOIN
    dim_customer c USING (customer_code)
ORDER BY forecast_accuracy DESC;



