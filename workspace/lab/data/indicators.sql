-- OHS Player Analytics — Materialized View Indicators
-- Run against the analytics database after each pipeline sync:
--   docker exec -i ohs-analytics-postgres psql -U postgres -d analytics < indicators/indicators.sql
--
-- Refresh all after an incremental pipeline run:
--   docker exec -i ohs-analytics-postgres psql -U postgres -d analytics -c "
--     SELECT indicators.refresh_all();"

CREATE SCHEMA IF NOT EXISTS indicators;

-- ─────────────────────────────────────────────────────────────────────────────
-- DIMENSION: Location hierarchy (village → subcounty → district → region)
-- Used as the primary join for all location-based indicators.
-- location_flat has forEachOrNull expansions so we deduplicate with DISTINCT ON.
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.dim_location CASCADE;
CREATE MATERIALIZED VIEW indicators.dim_location AS
WITH locs AS (
    SELECT DISTINCT ON (id) id, name, parent_location_id
    FROM location_flat
    ORDER BY id
)
SELECT
    v.id   AS village_id,    v.name AS village_name,
    s.id   AS subcounty_id,  s.name AS subcounty_name,
    d.id   AS district_id,   d.name AS district_name,
    r.id   AS region_id,     r.name AS region_name
FROM locs v
JOIN locs s ON s.id = v.parent_location_id
JOIN locs d ON d.id = s.parent_location_id
JOIN locs r ON r.id = d.parent_location_id
WHERE r.parent_location_id IS NULL
   OR r.parent_location_id NOT IN (SELECT id FROM locs);

CREATE UNIQUE INDEX ON indicators.dim_location (village_id);
CREATE INDEX ON indicators.dim_location (subcounty_id);
CREATE INDEX ON indicators.dim_location (district_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- DIMENSION: Patient with age group and resolved location names
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.dim_patient CASCADE;
CREATE MATERIALIZED VIEW indicators.dim_patient AS
SELECT
    p.id,
    p.gender,
    p.birth_date,
    CASE
        WHEN p.birth_date IS NULL THEN 'Unknown'
        WHEN date_part('year', age(p.birth_date::date)) <  5 THEN '0-4'
        WHEN date_part('year', age(p.birth_date::date)) < 15 THEN '5-14'
        WHEN date_part('year', age(p.birth_date::date)) < 25 THEN '15-24'
        WHEN date_part('year', age(p.birth_date::date)) < 50 THEN '25-49'
        ELSE '50+'
    END                           AS age_group,
    p.location_tag_id,
    p.practitioner_tag_id,
    p.org_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name
FROM patient_flat p
LEFT JOIN indicators.dim_location l ON l.village_id = p.location_tag_id;

CREATE UNIQUE INDEX ON indicators.dim_patient (id);
CREATE INDEX ON indicators.dim_patient (location_tag_id);
CREATE INDEX ON indicators.dim_patient (age_group, gender);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 1: Patient demographics — age/gender pyramid by location
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.patient_demographics CASCADE;
CREATE MATERIALIZED VIEW indicators.patient_demographics AS
SELECT
    dp.age_group,
    dp.gender,
    dp.village_name,
    dp.subcounty_name,
    dp.district_name,
    dp.region_name,
    count(*)                AS patient_count
FROM indicators.dim_patient dp
GROUP BY 1, 2, 3, 4, 5, 6;

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 2: Household registration summary by village
-- group_flat has member rows expanded; deduplicate on group id first.
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.household_summary CASCADE;
CREATE MATERIALIZED VIEW indicators.household_summary AS
WITH unique_groups AS (
    SELECT DISTINCT ON (id) id, village, location_tag_id, quantity
    FROM group_flat
    ORDER BY id
)
SELECT
    ug.village,
    ug.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name,
    count(*)                       AS household_count,
    sum(ug.quantity)               AS total_registered_members,
    round(avg(ug.quantity), 1)     AS avg_household_size
FROM unique_groups ug
LEFT JOIN indicators.dim_location l ON l.village_id = ug.location_tag_id
GROUP BY 1, 2, 3, 4, 5, 6;

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 3: Household composition — relationship types
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.household_composition CASCADE;
CREATE MATERIALIZED VIEW indicators.household_composition AS
SELECT
    rp.relationship_code,
    rp.relationship_display,
    rp.gender,
    CASE
        WHEN rp.birth_date IS NULL THEN 'Unknown'
        WHEN date_part('year', age(rp.birth_date::date)) <  5 THEN '0-4'
        WHEN date_part('year', age(rp.birth_date::date)) < 15 THEN '5-14'
        WHEN date_part('year', age(rp.birth_date::date)) < 25 THEN '15-24'
        WHEN date_part('year', age(rp.birth_date::date)) < 50 THEN '25-49'
        ELSE '50+'
    END                             AS age_group,
    count(*)                        AS count
FROM related_person_flat rp
GROUP BY 1, 2, 3, 4;

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 4: Monthly encounter volume by location and encounter class
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.monthly_encounters CASCADE;
CREATE MATERIALIZED VIEW indicators.monthly_encounters AS
SELECT
    date_trunc('month', e.period_start)::date   AS month,
    e.encounter_class,
    e.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name,
    count(*)                                    AS encounter_count,
    count(DISTINCT e.patient_id)                AS unique_patients
FROM encounter_flat e
LEFT JOIN indicators.dim_location l ON l.village_id = e.location_tag_id
WHERE e.period_start IS NOT NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7;

CREATE INDEX ON indicators.monthly_encounters (month);
CREATE INDEX ON indicators.monthly_encounters (location_tag_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 5: Program enrollments by month (Condition as enrollment record)
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.monthly_program_enrollments CASCADE;
CREATE MATERIALIZED VIEW indicators.monthly_program_enrollments AS
SELECT
    date_trunc('month', c.onset_datetime)::date AS enrollment_month,
    c.code_code                                 AS program_code,
    c.code_text                                 AS program_name,
    c.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name,
    count(DISTINCT c.patient_id)                AS new_enrollments
FROM condition_flat c
LEFT JOIN indicators.dim_location l ON l.village_id = c.location_tag_id
WHERE c.onset_datetime IS NOT NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

CREATE INDEX ON indicators.monthly_program_enrollments (enrollment_month);
CREATE INDEX ON indicators.monthly_program_enrollments (program_code);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 6: Active care plans — current program enrollment by location
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.active_care_plans CASCADE;
CREATE MATERIALIZED VIEW indicators.active_care_plans AS
SELECT
    cp.title               AS program_name,
    cp.status,
    cp.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name,
    count(*)               AS care_plan_count,
    count(DISTINCT cp.patient_id) AS unique_patients
FROM care_plan_flat cp
LEFT JOIN indicators.dim_location l ON l.village_id = cp.location_tag_id
GROUP BY 1, 2, 3, 4, 5, 6, 7;

CREATE INDEX ON indicators.active_care_plans (program_name);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 7: Observation summary — types, frequency, value presence by month
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.monthly_observations CASCADE;
CREATE MATERIALIZED VIEW indicators.monthly_observations AS
SELECT
    date_trunc('month', o.obs_date)::date  AS month,
    o.code_code,
    o.code_display,
    o.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    count(*)                               AS obs_count,
    count(DISTINCT o.patient_id)           AS unique_patients,
    count(o.val_string)                    AS with_string_value,
    count(o.val_quantity)                  AS with_quantity_value,
    avg(o.val_quantity)                    AS avg_quantity_value
FROM observation_flat o
LEFT JOIN indicators.dim_location l ON l.village_id = o.location_tag_id
WHERE o.obs_date IS NOT NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7;

CREATE INDEX ON indicators.monthly_observations (month);
CREATE INDEX ON indicators.monthly_observations (code_code);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 8: Monthly immunization delivery by vaccine type
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.monthly_immunizations CASCADE;
CREATE MATERIALIZED VIEW indicators.monthly_immunizations AS
SELECT
    date_trunc('month', i.occurrence_date)::date AS month,
    i.vaccine_code,
    i.vaccine_display,
    i.vaccine_short_name,
    i.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    l.region_name,
    count(*)                                     AS doses_given,
    count(DISTINCT i.patient_id)                 AS unique_children
FROM immunization_flat i
LEFT JOIN indicators.dim_location l ON l.village_id = i.location_tag_id
WHERE i.occurrence_date IS NOT NULL
  AND i.status = 'completed'
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9;

CREATE INDEX ON indicators.monthly_immunizations (month);
CREATE INDEX ON indicators.monthly_immunizations (vaccine_code);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 9: CHW workload — visits and unique patients per CHW per month
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.chw_workload CASCADE;
CREATE MATERIALIZED VIEW indicators.chw_workload AS
SELECT
    date_trunc('month', e.period_start)::date AS month,
    e.practitioner_tag_id                      AS chw_id,
    p.family                                   AS chw_family,
    p.given                                    AS chw_given,
    e.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    count(*)                                   AS visit_count,
    count(DISTINCT e.patient_id)               AS unique_patients_visited
FROM encounter_flat e
LEFT JOIN practitioner_flat p  ON p.id  = e.practitioner_tag_id
LEFT JOIN indicators.dim_location l ON l.village_id = e.location_tag_id
WHERE e.period_start IS NOT NULL
  AND e.practitioner_tag_id IS NOT NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

CREATE INDEX ON indicators.chw_workload (month);
CREATE INDEX ON indicators.chw_workload (chw_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- INDICATOR 10: Task status — open vs completed tasks per CHW per month
-- ─────────────────────────────────────────────────────────────────────────────
DROP MATERIALIZED VIEW IF EXISTS indicators.task_summary CASCADE;
CREATE MATERIALIZED VIEW indicators.task_summary AS
SELECT
    date_trunc('month', t.authored_on)::date AS month,
    t.owner_practitioner_id                   AS chw_id,
    p.family                                  AS chw_family,
    t.status,
    t.location_tag_id,
    l.village_name,
    l.subcounty_name,
    l.district_name,
    count(*)                                  AS task_count,
    count(DISTINCT t.patient_id)              AS unique_patients
FROM task_flat t
LEFT JOIN practitioner_flat p  ON p.id  = t.owner_practitioner_id
LEFT JOIN indicators.dim_location l ON l.village_id = t.location_tag_id
WHERE t.authored_on IS NOT NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

CREATE INDEX ON indicators.task_summary (month);
CREATE INDEX ON indicators.task_summary (chw_id);
CREATE INDEX ON indicators.task_summary (status);

-- ─────────────────────────────────────────────────────────────────────────────
-- REFRESH HELPER — call after each incremental pipeline sync
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION indicators.refresh_all()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY indicators.dim_location;
    REFRESH MATERIALIZED VIEW CONCURRENTLY indicators.dim_patient;
    REFRESH MATERIALIZED VIEW indicators.patient_demographics;
    REFRESH MATERIALIZED VIEW indicators.household_summary;
    REFRESH MATERIALIZED VIEW indicators.household_composition;
    REFRESH MATERIALIZED VIEW indicators.monthly_encounters;
    REFRESH MATERIALIZED VIEW indicators.monthly_program_enrollments;
    REFRESH MATERIALIZED VIEW indicators.active_care_plans;
    REFRESH MATERIALIZED VIEW indicators.monthly_observations;
    REFRESH MATERIALIZED VIEW indicators.monthly_immunizations;
    REFRESH MATERIALIZED VIEW indicators.chw_workload;
    REFRESH MATERIALIZED VIEW indicators.task_summary;
END;
$$;
