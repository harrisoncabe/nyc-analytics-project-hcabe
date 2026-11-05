-- Clean and standardize DOB NOW job application filings
-- One row per job filing number (job number + filing, e.g. M00512345-I1)

WITH source AS (
   SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
), -- Easier to refer to the dbt reference to a long name table this way

cleaned AS (
   SELECT
       -- Get all columns from source, except ones we're transforming below
       -- To do cleaning or renaming on them, or explicitly cast them as types
       * EXCEPT (
           job_filing_number,
           filing_status,
           job_type,
           filing_date,
           current_status_date,
           first_permit_date,
           approved_date,
           signoff_date,
           house_no,
           street_name,
           borough,
           bin,
           zip,
           initial_cost,
           latitude,
           longitude
       ),

       -- Identifiers - split the filing number into job number + filing suffix
       CAST(job_filing_number AS STRING) AS job_filing_number,
       SPLIT(job_filing_number, '-')[SAFE_OFFSET(0)] AS job_number,
       SPLIT(job_filing_number, '-')[SAFE_OFFSET(1)] AS filing_number,
       CAST(bin AS STRING) AS bin_number,

       -- Job details
       UPPER(TRIM(CAST(job_type AS STRING))) AS job_type,
       UPPER(TRIM(CAST(filing_status AS STRING))) AS filing_status,

       -- Dates - already timestamps, so just cast to DATE
       CAST(filing_date AS DATE) AS filing_date,
       CAST(current_status_date AS DATE) AS current_status_date,
       CAST(first_permit_date AS DATE) AS first_permit_date,
       CAST(approved_date AS DATE) AS approved_date,
       CAST(signoff_date AS DATE) AS signoff_date,

       -- Location - standardized borough, same logic as the 311 model
       CASE
           WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
           WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
           WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
           WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
           WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
           ELSE 'UNKNOWN or CITYWIDE'
       END AS borough,

       CAST(house_no AS STRING) AS house_number,
       CAST(street_name AS STRING) AS street_name,
       CAST(latitude AS DECIMAL) AS latitude,
       CAST(longitude AS DECIMAL) AS longitude,

       -- Zip - same cleaning logic as the 311 model
       CASE
           WHEN UPPER(TRIM(CAST(zip AS STRING))) IN ('N/A', 'NA') THEN NULL
           WHEN UPPER(TRIM(CAST(zip AS STRING))) = 'ANONYMOUS' THEN 'Anonymous'
           WHEN LENGTH(CAST(zip AS STRING)) = 5 THEN CAST(zip AS STRING)
           WHEN LENGTH(CAST(zip AS STRING)) = 9 THEN CAST(zip AS STRING)
           WHEN LENGTH(CAST(zip AS STRING)) = 10
               AND REGEXP_CONTAINS(CAST(zip AS STRING), r'^\d{5}-\d{4}')
           THEN CAST(zip AS STRING)
           ELSE NULL
       END AS zip,

       -- Cost - already numeric, cast to NUMERIC for exact money math
       SAFE_CAST(initial_cost AS NUMERIC) AS initial_cost,

       -- Metadata
       CURRENT_TIMESTAMP() AS _stg_loaded_at

   FROM source

   -- Filters
   WHERE job_filing_number IS NOT NULL
   AND borough IS NOT NULL
   AND CAST(filing_date AS DATE) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 YEAR)

   -- Deduplicate - one row per job filing, keeping the latest status update
   QUALIFY ROW_NUMBER() OVER (
       PARTITION BY job_filing_number
       ORDER BY current_status_date DESC
   ) = 1
)

SELECT * FROM cleaned
-- All should be part of this table after running: stg_nyc_dob_job_filings