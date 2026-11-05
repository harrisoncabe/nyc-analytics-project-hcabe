-- Location dimension shared by both data sources
-- Grain: one row per distinct combination of borough / council_district / zip.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_nyc_311_dot') }}
),

stg_dob AS (
    SELECT * FROM {{ ref('stg_nyc_dob_job_filings') }}
),

all_locations AS (

    SELECT DISTINCT
        borough,
        CAST(council_district AS STRING) AS council_district,
        CAST(zip AS STRING) AS zip
    FROM stg_311
    WHERE borough IS NOT NULL
       OR council_district IS NOT NULL
       OR zip IS NOT NULL

    UNION DISTINCT

    SELECT DISTINCT
        borough,
        CAST(council_district AS STRING) AS council_district,
        CAST(zip AS STRING) AS zip
    FROM stg_dob
    WHERE borough IS NOT NULL
       OR council_district IS NOT NULL
       OR zip IS NOT NULL

),

location_dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'borough', 'council_district', 'zip'
        ]) }} AS location_key,

        borough,
        council_district,
        zip

    FROM all_locations

),

-- Null placeholder row to handle NULL values.

null_placeholder AS (

    SELECT
        '-1' AS location_key,
        CAST(NULL AS STRING) AS borough,
        CAST(NULL AS STRING) AS council_district,
        CAST(NULL AS STRING) AS zip

)

SELECT location_key, borough, council_district, zip FROM location_dimension
UNION ALL
SELECT location_key, borough, council_district, zip FROM null_placeholder



You’ll need to replace the question marks (“?????”) with something else in each case. 

When you are ready to try running it, in the dbt IDE,

dbt build --select dim_location

If you get an error, for example if you replaced the ???? incorrectly – stay calm and change one thing at a time to debug until it runs successfully.

Then save and commit.

Consider what just happened
Check out the code above again, specifically this part:


location_dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'borough', 'council_district', 'zip'
        ]) }} AS location_key,

        borough,
        council_district,
        zip

    FROM all_locations

),

