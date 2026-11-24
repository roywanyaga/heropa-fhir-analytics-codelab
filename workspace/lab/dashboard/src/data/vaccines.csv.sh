#!/usr/bin/env bash
# Vaccine doses by vaccine and month.
source "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample vaccines.csv <<'SQL'
SELECT to_char(date_trunc('month', occurrence_date::timestamp), 'YYYY-MM') AS month,
       coalesce(vaccine_short_name, 'Other') AS vaccine,
       count(DISTINCT id) AS doses
FROM immunization_flat
WHERE occurrence_date IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
SQL
