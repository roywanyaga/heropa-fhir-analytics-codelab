#!/bin/sh
# One row for each number at the top of the Overview page.
# The flat tables repeat a resource when it has several codings or performers,
# so every count is of distinct ids.
. "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample kpis.csv <<'SQL'
SELECT 'Patients'      AS metric, count(DISTINCT id) AS value FROM patient_flat
UNION ALL
SELECT 'Households',    count(DISTINCT id) FROM group_flat
UNION ALL
SELECT 'Visits',        count(DISTINCT id) FROM encounter_flat
UNION ALL
SELECT 'Vaccine doses', count(DISTINCT id) FROM immunization_flat;
SQL
