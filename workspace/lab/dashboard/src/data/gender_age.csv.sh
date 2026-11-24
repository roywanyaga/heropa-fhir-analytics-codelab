#!/bin/sh
# Patients by gender and age group.
. "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample gender_age.csv <<'SQL'
SELECT
  coalesce(gender, 'unknown') AS gender,
  CASE
    WHEN birth_date IS NULL THEN 'Unknown'
    WHEN date_part('year', age(birth_date::date)) <  5 THEN '0-4'
    WHEN date_part('year', age(birth_date::date)) < 15 THEN '5-14'
    WHEN date_part('year', age(birth_date::date)) < 25 THEN '15-24'
    WHEN date_part('year', age(birth_date::date)) < 50 THEN '25-49'
    ELSE '50+'
  END AS age_group,
  count(DISTINCT id) AS patients
FROM patient_flat
GROUP BY 1, 2
ORDER BY 2, 1;
SQL
