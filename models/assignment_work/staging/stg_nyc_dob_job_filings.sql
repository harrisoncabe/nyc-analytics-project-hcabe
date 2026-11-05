-- Clean and standardize DOB job application filings
-- One row per job number + document number

WITH source AS (
   SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
), -- Easier to refer to the dbt reference to a long name table this way

cleaned AS (
   SELECT
       -- Get all columns from source, except ones we're transforming below
       -- To do cleaning or renaming on them, or explicitly cast them as types
       * EXCEPT (
           job__,
           doc__,
           bin__,
           job_type,
           job_status,
           job_status_descrp,
           pre__filing_date,
           approved,
           fully_permitted,
           signoff_date,
           latest_action_date,
           borough,
           house__,
           street_name,
           gis_latitude,
           gis_longitude,
           initial_cost,
           total_est__fee,
           existing_dwelling_units,
           proposed_dwelling_units,
           zip
       ),

       -- Identifiers - kept as strings so leading zeros survive (e.g. doc '01')
       CAST(job__ AS STRING) AS job_number,
       CAST(doc__ AS STRING) AS doc_number,
       CAST(bin__ AS STRING) AS bin_number,

       -- Job details
       UPPER(TRIM(CAST(job_type AS STRING))) AS job_type,
       UPPER(TRIM(CAST(job_status AS STRING))) AS job_status,
       CAST(job_status_descrp AS STRING) AS job_status_description,

       -- Dates - MM/DD/YYYY text to DATE (LEFT 10 drops any trailing time)
       SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(pre__filing_date AS STRING)), 10)) AS pre_filing_date,
       SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(approved AS STRING)), 10)) AS approved_date,
       SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(fully_permitted AS STRING)), 10)) AS fully_permitted_date,
       SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(signoff_date AS STRING)), 10)) AS signoff_date,
       SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(latest_action_date AS STRING)), 10)) AS latest_action_date,

       -- Location - standardized borough, same logic as the 311 model
       CASE
           WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
           WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
           WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
           WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
           WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
           ELSE 'UNKNOWN or CITYWIDE'
       END AS borough,

       CAST(house__ AS STRING) AS house_number,
       CAST(street_name AS STRING) AS street_name,
       CAST(gis_latitude AS DECIMAL) AS latitude,
       CAST(gis_longitude AS DECIMAL) AS longitude,

       -- Cost - strip $ and commas, then cast to a number
       SAFE_CAST(REGEXP_REPLACE(CAST(initial_cost AS STRING), r'[$,]', '') AS NUMERIC) AS initial_cost,
       SAFE_CAST(REGEXP_REPLACE(CAST(total_est__fee AS STRING), r'[$,]', '') AS NUMERIC) AS total_est_fee,

       -- Dwelling units
       SAFE_CAST(existing_dwelling_units AS INT64) AS existing_dwelling_units,
       SAFE_CAST(proposed_dwelling_units AS INT64) AS proposed_dwelling_units,

       -- Owner zip - same cleaning logic as the 311 model
       CASE
           WHEN UPPER(TRIM(CAST(zip AS STRING))) IN ('N/A', 'NA') THEN NULL
           WHEN UPPER(TRIM(CAST(zip AS STRING))) = 'ANONYMOUS' THEN 'Anonymous'
           WHEN LENGTH(CAST(zip AS STRING)) = 5 THEN CAST(zip AS STRING)
           WHEN LENGTH(CAST(zip AS STRING)) = 9 THEN CAST(zip AS STRING)
           WHEN LENGTH(CAST(zip AS STRING)) = 10
               AND REGEXP_CONTAINS(CAST(zip AS STRING), r'^\d{5}-\d{4}')
           THEN CAST(zip AS STRING)
           ELSE NULL
       END AS owner_zip,

       -- Metadata
       CURRENT_TIMESTAMP() AS _stg_loaded_at

   FROM source

   -- Filters
   WHERE job__ IS NOT NULL
   AND doc__ IS NOT NULL
   AND borough IS NOT NULL
   AND SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(pre__filing_date AS STRING)), 10))
       >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 YEAR)

   -- Deduplicate - one row per job + doc, keeping the latest action
   QUALIFY ROW_NUMBER() OVER (
       PARTITION BY job__, doc__
       ORDER BY SAFE.PARSE_DATE('%m/%d/%Y', LEFT(TRIM(CAST(latest_action_date AS STRING)), 10)) DESC
   ) = 1
)

SELECT * FROM cleaned
-- All should be part of this table after running: stg_nyc_dob_job_filings