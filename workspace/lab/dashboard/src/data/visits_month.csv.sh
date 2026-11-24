#!/bin/sh
# Visits (Encounters) per month.
. "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample visits_month.csv <<'SQL'
SELECT to_char(date_trunc('month', period_start::timestamp), 'YYYY-MM') AS month,
       count(DISTINCT id) AS visits
FROM encounter_flat
WHERE period_start IS NOT NULL
GROUP BY 1
ORDER BY 1;
SQL
