#!/bin/sh
# How many rows each flat table holds. Rows are counted by distinct id, so a
# resource that has two codings is still counted once. This is the number to
# watch while the pipeline runs.
. "$(dirname "$0")/../../scripts/lib.sh"
query_or_sample tables.csv <<'SQL'
SELECT 'Patient' AS resource, count(DISTINCT id) AS rows FROM patient_flat
UNION ALL SELECT 'Group',        count(DISTINCT id) FROM group_flat
UNION ALL SELECT 'Encounter',    count(DISTINCT id) FROM encounter_flat
UNION ALL SELECT 'Condition',    count(DISTINCT id) FROM condition_flat
UNION ALL SELECT 'Observation',  count(DISTINCT id) FROM observation_flat
UNION ALL SELECT 'Immunization', count(DISTINCT id) FROM immunization_flat;
SQL
