#!/bin/sh
# New programme enrolments per month. A Condition is the enrolment record.
. "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample enrolments_month.csv <<'SQL'
SELECT to_char(date_trunc('month', coalesce(onset_datetime, recorded_date)::timestamp), 'YYYY-MM') AS month,
       coalesce(code_text, 'Other') AS programme,
       count(DISTINCT id) AS enrolments
FROM condition_flat
WHERE coalesce(onset_datetime, recorded_date) IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
SQL
