#!/usr/bin/env python3
"""
OHS FHIR Analytics codelab — Synthetic FHIR Data Generator

Adapted from ohs-player-analytics/test-data/generate.py. Adds --villages and --seed,
and adds the Sengmany family of the SMART Trust demonstrator to one village.

Generates a time-distributed dataset for analytics development.
Data spans Jan 2025 – Jun 2026 so monthly trend charts have 18 months of data.

Default scale (~10 k patients):
  50 villages · 50 households/village · ~4 patients/household
  Programs: HIV, Family Planning, ANC, PNC, Sick Child, TB, Hypertension, Malaria

Usage:
  python generate.py [--fhir-url URL] [--patients N] [--batch-size N] [--dry-run]

Dependencies:  pip install requests
"""

import argparse
import random
import sys
import uuid
from datetime import date, timedelta

import requests

# ─────────────────────────────────────────────────────────────
# Time window
# ─────────────────────────────────────────────────────────────

DATA_START = date(2025, 1, 1)
DATA_END   = date(2026, 11, 20)

APP_VERSION  = "1.0.0-ohs"
FHIR_SNOMED  = "http://snomed.info/sct"
NUM_VILLAGES = 50

# ─────────────────────────────────────────────────────────────
# Programs
# Each entry drives condition creation + encounter cadence.
# ─────────────────────────────────────────────────────────────

PROGRAMS = [
    {
        "id": "hiv",
        "code": "165816005", "display": "HIV infection", "text": "HIV",
        "system": FHIR_SNOMED, "chronic": True,
        "interval_days": 30,  "max_encounters": None,
        "genders": None,    "age_min": 15, "age_max": 99, "prob": 0.12,
    },
    {
        "id": "family_planning",
        "code": "408969000", "display": "Family Planning", "text": "Family Planning",
        "system": FHIR_SNOMED, "chronic": False,
        "interval_days": 90,  "max_encounters": None,
        "genders": ["female"], "age_min": 15, "age_max": 49, "prob": 0.80,
    },
    {
        "id": "anc",
        "code": "77386006", "display": "Pregnant", "text": "Pregnant",
        "system": FHIR_SNOMED, "chronic": False,
        "interval_days": 28,  "max_encounters": 4,
        "genders": ["female"], "age_min": 15, "age_max": 49, "prob": 0.25,
    },
    {
        "id": "pnc",
        "code": "133906008", "display": "PNC", "text": "PNC",
        "system": FHIR_SNOMED, "chronic": False,
        "interval_days": 30,  "max_encounters": 3,
        "genders": ["female"], "age_min": 15, "age_max": 49, "prob": 0.15,
    },
    {
        "id": "sick_child",
        "code": "275142008", "display": "Sick Child", "text": "Sick Child",
        "system": FHIR_SNOMED, "chronic": False,
        "interval_days": 45,  "max_encounters": None,
        "genders": None,    "age_min": 0, "age_max": 4,  "prob": 0.70,
    },
    {
        "id": "tb",
        "code": "371569005", "display": "TB Condition", "text": "TB Condition",
        "system": FHIR_SNOMED, "chronic": True,
        "interval_days": 30,  "max_encounters": 6,
        "genders": None,    "age_min": 15, "age_max": 99, "prob": 0.06,
    },
    {
        "id": "hypertension",
        "code": "38341003",
        "display": "Hypertensive disorder, systemic arterial", "text": "Hypertension",
        "system": FHIR_SNOMED, "chronic": True,
        "interval_days": 30,  "max_encounters": None,
        "genders": None,    "age_min": 35, "age_max": 99, "prob": 0.22,
    },
    {
        "id": "malaria",
        "code": "61462000", "display": "Malaria", "text": "Malaria",
        "system": FHIR_SNOMED, "chronic": False,
        "interval_days": 7,   "max_encounters": 3,
        "genders": None,    "age_min": 0, "age_max": 99, "prob": 0.25,
    },
]

PROG_BY_ID = {p["id"]: p for p in PROGRAMS}

VACCINES = [
    {"code": "33490001",  "display": "BCG vaccine",         "shortName": "BCG"},
    {"code": "412375000", "display": "Hepatitis B vaccine",  "shortName": "Hep B"},
    {"code": "396429000", "display": "Oral polio vaccine",   "shortName": "OPV"},
    {"code": "116077000", "display": "Pentavalent vaccine",  "shortName": "Penta"},
    {"code": "871875004", "display": "Measles vaccine",      "shortName": "Measles"},
    {"code": "400448000", "display": "Rotavirus vaccine",    "shortName": "Rotavirus"},
]

OBS_CODES = [
    {"code": "713601003", "display": "Household visit"},
    {"code": "171207006", "display": "Pregnancy diet education"},
    {"code": "413473000", "display": "HIV risk reduction counseling"},
    {"code": "409073007", "display": "Counseling"},
    {"code": "268562009", "display": "Antenatal care"},
    {"code": "171219009", "display": "Child health surveillance"},
    {"code": "386053000", "display": "Evaluation procedure"},
    {"code": "410284003", "display": "Medication management"},
]

QUESTIONNAIRES = {
    "hiv":            "hiv-screening-v1",
    "family_planning":"family-planning-visit-v1",
    "anc":            "anc-visit-v1",
    "pnc":            "pnc-visit-v1",
    "sick_child":     "child-health-visit-v1",
    "tb":             "tb-screening-v1",
    "hypertension":   "hypertension-follow-up-v1",
    "malaria":        "malaria-treatment-v1",
}

TASK_DESCRIPTIONS = [
    "Schedule follow-up visit",
    "Ensure medication adherence",
    "Conduct home visit",
    "Refer patient to health facility",
    "Monitor blood pressure",
    "Provide health education on nutrition",
    "Conduct ANC follow-up",
    "Screen household members for TB contacts",
    "HIV testing and counseling follow-up",
    "Check immunization schedule is current",
]

# ─────────────────────────────────────────────────────────────
# Uganda names and places
# ─────────────────────────────────────────────────────────────

DISTRICTS = ["Nakawa", "Kawempe", "Rubaga"]

SUBCOUNTIES = [
    "Kinawataka", "Kyanja", "Ntinda", "Naguru",
    "Kanyanya", "Makerere", "Bukoto", "Mpererwe",
    "Mengo", "Lubaga", "Mutundwe", "Busega",
]

# Exactly 50 villages
VILLAGE_NAMES = [
    "Kasokoso", "Kireka", "Bweyogerere", "Bukoto East", "Naguru Hill",
    "Kamwokya", "Mulago", "Kitintale", "Naguru", "Bukasa",
    "Kyanja A", "Kyanja B", "Ntinda Market", "Kiwatule", "Nakawa Estate",
    "Makerere Hill", "Wandegeya", "Kikoni", "Katanga", "Bwaise",
    "Kanyanya A", "Kanyanya B", "Mpererwe", "Kazo", "Ttula",
    "Lubaga A", "Lubaga B", "Namirembe", "Kasubi", "Ndeeba",
    "Mutundwe A", "Mutundwe B", "Konge", "Nalya", "Luzira",
    "Bugolobi", "Mbuya", "Banda", "Namuwongo", "Kabalagala",
    "Buziga", "Ggaba", "Munyonyo", "Makindye", "Zana",
    "Lubowa", "Seguku", "Najanankumbi", "Kira", "Namugongo",
]

MALE_FIRST = [
    "Ssekitto", "Kibuuka", "Wasswa", "Wamala", "Kiwanuka", "Mukasa", "Ssenoga",
    "Kyeyune", "Bbosa", "Kasozi", "Lutalo", "Sentamu", "Musoke", "Kawuki",
    "Sekanjako", "Katumba", "Mubiru", "Tumusiime", "Byaruhanga", "Nkurunziza",
    "Ssemakula", "Kato", "Mulindwa", "Kagwa", "Sserunjogi",
]
FEMALE_FIRST = [
    "Nakato", "Namukasa", "Nalwanga", "Nankya", "Nassuna", "Nambi", "Nakabugo",
    "Nantongo", "Nalubega", "Namusisi", "Nansubuga", "Nabwire", "Nakayima",
    "Najjemba", "Namuddu", "Nambatya", "Nakimuli", "Nabirye", "Naturinda", "Akello",
    "Amoding", "Apio", "Acen", "Atim", "Aber",
]
FAMILY_NAMES = [
    "Ssemanda", "Kiggundu", "Nabukenya", "Ssekandi", "Mutebi", "Nantaba",
    "Kalibbala", "Luyirika", "Nnyanzi", "Businge", "Nsubuga", "Kironde",
    "Kateregga", "Ssebaggala", "Mukyala", "Okello", "Ochan", "Omara",
    "Mugisha", "Tumwine", "Rwabukwali", "Kansiime", "Atuhaire", "Tibemanya",
    "Byamukama", "Tumwebaze", "Kashaija", "Muhwezi", "Kemigisha", "Birungi",
]

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def new_id():
    return str(uuid.uuid4())

def rand_date(start=DATA_START, end=DATA_END):
    return start + timedelta(days=random.randint(0, (end - start).days))

def rand_phone():
    prefix = random.choice(["0701", "0702", "0703", "0704", "0751", "0772", "0774", "0775", "0776"])
    return f"{prefix} {random.randint(100000, 999999)}"

def rand_name(gender):
    given  = random.choice(MALE_FIRST if gender == "male" else FEMALE_FIRST)
    family = random.choice(FAMILY_NAMES)
    return given, family

def numeric_id():
    return str(random.randint(200000, 899999))

def dt_str(d):
    h = random.randint(8, 17)
    m = random.randint(0, 59)
    return f"{d}T{h:02d}:{m:02d}:00+03:00"

def meta_tags(pract_id, org_id, loc_id, ct_id):
    return {"tag": [
        {"code": APP_VERSION, "system": "https://smartregister.org/app-version",         "display": "Application Version"},
        {"code": pract_id,   "system": "https://smartregister.org/practitioner-tag-id",  "display": "Practitioner"},
        {"code": org_id,     "system": "https://smartregister.org/organisation-tag-id",  "display": "Practitioner Organization"},
        {"code": ct_id,      "system": "https://smartregister.org/care-team-tag-id",     "display": "Practitioner CareTeam"},
        {"code": loc_id,     "system": "https://smartregister.org/location-tag-id",      "display": "Practitioner Location"},
    ]}

def mk_ids(official, secondary=None):
    result = [{"use": "official", "value": official}]
    if secondary:
        result.append({"use": "secondary", "value": secondary})
    return result

def encounter_dates(enrollment_date, interval_days, max_encounters):
    dates, d = [], enrollment_date
    while d <= DATA_END:
        dates.append(d)
        d += timedelta(days=interval_days)
        if max_encounters and len(dates) >= max_encounters:
            break
    return dates

def eligible_programs(gender, age):
    enrolled = []
    for prog in PROGRAMS:
        if prog["genders"] and gender not in prog["genders"]:
            continue
        if not (prog["age_min"] <= age <= prog["age_max"]):
            continue
        if random.random() <= prog["prob"]:
            enrolled.append(prog["id"])
    # ANC is mutually exclusive with FP and PNC
    if "anc" in enrolled:
        enrolled = [p for p in enrolled if p not in ("family_planning", "pnc")]
    return enrolled

# ─────────────────────────────────────────────────────────────
# Resource builders
# ─────────────────────────────────────────────────────────────

def mk_location(name, part_of_id=None):
    rid = new_id()
    res = {
        "resourceType": "Location", "id": rid, "name": name, "status": "active",
        "identifier": mk_ids(new_id()),
        "physicalType": {"coding": [{"code": "jdn",
            "system": "http://terminology.hl7.org/CodeSystem/location-physical-type",
            "display": "Jurisdiction"}]},
    }
    if part_of_id:
        res["partOf"] = {"reference": f"Location/{part_of_id}"}
    return rid, res

def mk_org(name):
    rid = new_id()
    return rid, {
        "resourceType": "Organization", "id": rid, "name": name, "active": True,
        "type": [{"coding": [{"code": "team",
            "system": "http://terminology.hl7.org/CodeSystem/organization-type"}]}],
        "identifier": mk_ids(rid),
    }

def mk_practitioner(gender):
    rid = new_id()
    given, family = rand_name(gender)
    return rid, f"{given} {family}", {
        "resourceType": "Practitioner", "id": rid, "active": True,
        "name": [{"use": "official", "given": [given], "family": family}],
        "telecom": [{"value": rand_phone(), "system": "email"}],
        "identifier": mk_ids(rid, new_id()),
    }

def mk_practitioner_role(p_id, p_display, org_id, org_display, role_code, role_display,
                         loc_id=None, loc_display=None):
    rid = new_id()
    res = {
        "resourceType": "PractitionerRole", "id": rid, "active": True,
        "identifier": mk_ids(rid, new_id()),
        "practitioner": {"display": p_display,  "reference": f"Practitioner/{p_id}"},
        "organization":  {"display": org_display, "reference": f"Organization/{org_id}"},
        "code": [{"coding": [{"code": role_code, "system": FHIR_SNOMED, "display": role_display}]}],
    }
    if loc_id:
        res["location"] = [{"reference": f"Location/{loc_id}", "display": loc_display or loc_id}]
    return rid, res

def mk_care_team(name, org_id, org_display, members):
    rid = new_id()
    participants = [{
        "role": [{"coding": [{"code": "394730007", "system": FHIR_SNOMED,
                              "display": "Healthcare related organization"}]}],
        "member": {"display": org_display, "reference": f"Organization/{org_id}"},
    }] + [{"member": {"display": d, "reference": f"Practitioner/{p}"}} for p, d in members]
    return rid, {
        "resourceType": "CareTeam", "id": rid, "name": name, "status": "active",
        "identifier": mk_ids(rid),
        "participant": participants,
        "managingOrganization": [{"display": org_display, "reference": f"Organization/{org_id}"}],
    }

def mk_group(name, v_id, v_name, chw_id, org_id, ct_id):
    rid = new_id()
    start = rand_date(DATA_START, DATA_START + timedelta(days=60))
    return rid, {
        "resourceType": "Group", "id": rid, "active": True, "type": "person",
        "code": {"coding": [{"code": "35359004", "system": "https://www.snomed.org", "display": "Family"}]},
        "name": name,
        "identifier": [
            {"use": "official",  "value": numeric_id(), "period": {"start": f"{start}T09:00:00+03:00"}},
            {"use": "secondary", "value": new_id()},
        ],
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
        "characteristic": [{"code": {
            "text": v_name,
            "coding": [{"code": "hh_location", "system": "http://ona.io/codes", "display": "Household Location"}],
        }, "exclude": False}],
        "managingEntity": {"reference": f"Organization/{org_id}"},
    }

def mk_patient(gender, birth_year, chw_id, org_id, ct_id, v_id, enroll_date):
    rid = new_id()
    given, family = rand_name(gender)
    birth = date(birth_year, random.randint(1, 12), random.randint(1, 28))
    return rid, f"{given} {family}", {
        "resourceType": "Patient", "id": rid, "active": True,
        "gender": gender, "birthDate": str(birth), "deceasedBoolean": False,
        "name": [{"use": "official", "given": [given], "family": family}],
        "telecom": [{"system": "phone"}],
        "identifier": [
            {"use": "official",  "value": numeric_id(), "period": {"start": f"{enroll_date}T09:00:00+03:00"}},
            {"use": "secondary", "value": new_id(),     "period": {"start": f"{enroll_date}T09:00:00+03:00"}},
        ],
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
        "generalPractitioner": [{"reference": f"Practitioner/{chw_id}"}],
        "managingOrganization": {"reference": f"Organization/{org_id}"},
    }

def mk_related_person(patient_id, patient_display):
    rid = new_id()
    given, family = rand_name(random.choice(["male", "female"]))
    return rid, {
        "resourceType": "RelatedPerson", "id": rid, "active": True,
        "patient": {"reference": f"Patient/{patient_id}", "display": patient_display},
        "relationship": [{"coding": [{"code": "SPS",
            "system": "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "display": "Spouse"}]}],
        "name": [{"use": "official", "given": [given], "family": family}],
        "telecom": [{"system": "phone", "value": rand_phone()}],
        "identifier": mk_ids(new_id()),
    }

def mk_encounter(pat_id, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    dt = dt_str(d)
    return rid, {
        "resourceType": "Encounter", "id": rid, "status": "finished",
        "class": {"code": "HH", "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode"},
        "period": {"start": dt, "end": dt},
        "subject": {"reference": f"Patient/{pat_id}"},
        "participant": [{"individual": {"reference": f"Practitioner/{chw_id}"}}],
        "serviceProvider": {"reference": f"Organization/{org_id}"},
        "serviceType": {"coding": [{"code": "33879002",
            "system": "http://terminology.hl7.org/CodeSystem/service-type"}]},
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_condition(pat_id, enc_id, prog, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    dt = dt_str(d)
    return rid, {
        "resourceType": "Condition", "id": rid,
        "code": {"text": prog["text"], "coding": [{"code": prog["code"],
            "system": prog["system"], "display": prog["display"]}]},
        "subject":  {"reference": f"Patient/{pat_id}"},
        "encounter": {"reference": f"Encounter/{enc_id}"},
        "category": [{"coding": [{"code": "problem-list-item",
            "system": "http://terminology.hl7.org/CodeSystem/condition-category"}]}],
        "clinicalStatus":      {"coding": [{"code": "active",
            "system": "http://terminology.hl7.org/CodeSystem/condition-clinical"}]},
        "verificationStatus":  {"coding": [{"code": "confirmed",
            "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status"}]},
        "onsetDateTime": dt, "recordedDate": dt,
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_observation(pat_id, enc_id, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    obs = random.choice(OBS_CODES)
    return rid, {
        "resourceType": "Observation", "id": rid, "status": "final",
        "code": {"text": obs["display"], "coding": [{"code": obs["code"],
            "system": FHIR_SNOMED, "display": obs["display"]}]},
        "category": [{"coding": [{"code": "social-history",
            "system": "http://terminology.hl7.org/CodeSystem/observation-category"}]}],
        "subject":  {"reference": f"Patient/{pat_id}"},
        "encounter": {"reference": f"Encounter/{enc_id}"},
        "performer": [{"reference": f"Practitioner/{chw_id}"}],
        "valueString": random.choice(["yes", "no", "done", "referred", "counseled"]),
        "effectiveDateTime": dt_str(d),
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_immunization(pat_id, enc_id, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    vac = random.choice(VACCINES)
    return rid, {
        "resourceType": "Immunization", "id": rid, "status": "completed",
        "vaccineCode": {"text": vac["shortName"], "coding": [{"code": vac["code"],
            "system": FHIR_SNOMED, "display": vac["display"]}]},
        "patient":  {"reference": f"Patient/{pat_id}"},
        "encounter": {"reference": f"Encounter/{enc_id}"},
        "occurrenceDateTime": dt_str(d),
        "performer": [{"actor": {"reference": f"Practitioner/{chw_id}"}}],
        "primarySource": True,
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_care_plan(pat_id, enc_id, cond_id, prog, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    return rid, {
        "resourceType": "CarePlan", "id": rid, "status": "active", "intent": "plan",
        "title": f"Care Plan — {prog['text']}",
        "category": [{"coding": [{"code": "736368003", "system": FHIR_SNOMED,
            "display": "Nursing care plan"}]}],
        "subject":  {"reference": f"Patient/{pat_id}"},
        "encounter": {"reference": f"Encounter/{enc_id}"},
        "period": {"start": str(d), "end": str(d + timedelta(days=365))},
        "addresses": [{"reference": f"Condition/{cond_id}"}],
        "author":    {"reference": f"Practitioner/{chw_id}"},
        "careTeam":  [{"reference": f"Organization/{org_id}"}],
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_task(pat_id, cp_id, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    dt = dt_str(d)
    return rid, {
        "resourceType": "Task", "id": rid,
        "status": random.choice(["requested", "in-progress", "completed"]),
        "intent": "order", "priority": "routine",
        "description": random.choice(TASK_DESCRIPTIONS),
        "for":       {"reference": f"Patient/{pat_id}"},
        "focus":     {"reference": f"CarePlan/{cp_id}"},
        "owner":     {"reference": f"Practitioner/{chw_id}"},
        "requester": {"reference": f"Organization/{org_id}"},
        "authoredOn": dt, "lastModified": dt,
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }

def mk_qr(pat_id, enc_id, prog_id, chw_id, org_id, ct_id, v_id, d):
    rid = new_id()
    dt = dt_str(d)
    return rid, {
        "resourceType": "QuestionnaireResponse", "id": rid,
        "questionnaire": f"Questionnaire/{QUESTIONNAIRES.get(prog_id, 'general-household-visit-v1')}",
        "status": "completed",
        "subject":  {"reference": f"Patient/{pat_id}"},
        "encounter": {"reference": f"Encounter/{enc_id}"},
        "authored": dt,
        "author":   {"reference": f"Practitioner/{chw_id}"},
        "item": [
            {"linkId": "visit-date",        "text": "Visit Date",
             "answer": [{"valueDate": str(d)}]},
            {"linkId": "visit-reason",      "text": "Reason for Visit",
             "answer": [{"valueString": random.choice(["Routine visit", "Follow-up", "New enrollment", "Referral follow-up"])}]},
            {"linkId": "services-provided", "text": "Services Provided",
             "answer": [{"valueString": random.choice(["Counseling", "Health education", "Referral", "Treatment", "Immunization"])}]},
        ],
        "meta": meta_tags(chw_id, org_id, v_id, ct_id),
    }


# ─────────────────────────────────────────────────────────────
# FHIR client — batch bundle mode
# ─────────────────────────────────────────────────────────────

class FHIRClient:
    def __init__(self, base_url, dry_run=False, batch_size=500):
        self.base_url   = base_url.rstrip("/")
        self.dry_run    = dry_run
        self.batch_size = batch_size
        self._pending   = []
        self.counts     = {}
        self.errors     = 0

    def add(self, resource):
        rt = resource["resourceType"]
        self.counts[rt] = self.counts.get(rt, 0) + 1
        if self.dry_run:
            return
        self._pending.append(resource)
        if len(self._pending) >= self.batch_size:
            self._flush()

    def flush(self):
        if self._pending:
            self._flush()

    def _flush(self):
        bundle = {
            "resourceType": "Bundle", "type": "batch",
            "entry": [
                {"resource": r, "request": {"method": "PUT", "url": f"{r['resourceType']}/{r['id']}"}}
                for r in self._pending
            ],
        }
        try:
            resp = requests.post(
                self.base_url, json=bundle,
                headers={"Content-Type": "application/fhir+json"},
                timeout=120,
            )
            if resp.status_code not in (200, 201):
                print(f"\n  BATCH ERROR {resp.status_code}: {resp.text[:300]}", file=sys.stderr)
                self.errors += 1
        except requests.RequestException as exc:
            print(f"\n  BATCH ERROR: {exc}", file=sys.stderr)
            self.errors += 1
        self._pending = []

    def total(self):
        return sum(self.counts.values())

    def summary(self):
        label = "Would generate" if self.dry_run else "Loaded"
        print(f"\n{label} {self.total():,} resources:")
        for rt in sorted(self.counts):
            print(f"  {rt:35s} {self.counts[rt]:>8,}")
        if self.errors:
            print(f"\n  {self.errors} batch error(s) — check stderr for details.")


# ─────────────────────────────────────────────────────────────
# Infrastructure (locations, orgs, practitioners, care teams)
# ─────────────────────────────────────────────────────────────

def build_infrastructure(client):
    print("  Locations...", flush=True)
    region_id, region = mk_location("Kampala Region")
    client.add(region)

    district_ids = []
    for name in DISTRICTS:
        d_id, d = mk_location(f"{name} District", part_of_id=region_id)
        client.add(d)
        district_ids.append(d_id)

    subcounty_data = []  # (sc_id, sc_name)
    for i, name in enumerate(SUBCOUNTIES):
        sc_id, sc = mk_location(f"{name} Sub-County", part_of_id=district_ids[i % len(district_ids)])
        client.add(sc)
        subcounty_data.append((sc_id, f"{name} Sub-County"))

    village_data = []  # (v_id, v_name, sc_id)
    for i, name in enumerate(VILLAGE_NAMES):
        sc_id, _ = subcounty_data[i % len(subcounty_data)]
        v_id, v = mk_location(f"{name} Village", part_of_id=sc_id)
        client.add(v)
        village_data.append((v_id, f"{name} Village", sc_id))

    print("  Organizations & practitioners...", flush=True)
    sup_org_id, sup_org = mk_org("Kampala Division Supervisor Org")
    client.add(sup_org)

    # One CHW org per sub-county
    chw_org_by_sc = {}
    for sc_id, sc_name in subcounty_data:
        org_id, org = mk_org(f"{sc_name} CHW Team")
        client.add(org)
        chw_org_by_sc[sc_id] = (org_id, org["name"])

    # Supervisors — 1 per sub-county
    for i, (sc_id, sc_name) in enumerate(subcounty_data):
        p_id, display, p = mk_practitioner("female" if i % 2 == 0 else "male")
        client.add(p)
        _, role = mk_practitioner_role(
            p_id, display, sup_org_id, sup_org["name"],
            "236321002", "Supervisor (occupation)",
            loc_id=sc_id, loc_display=sc_name,
        )
        client.add(role)

    # CHWs — 2 per village
    chw_by_village = {}
    for v_id, v_name, sc_id in village_data:
        org_id, org_name = chw_org_by_sc[sc_id]
        chws = []
        for j in range(2):
            p_id, display, p = mk_practitioner("female" if j == 0 else "male")
            client.add(p)
            _, role = mk_practitioner_role(
                p_id, display, org_id, org_name,
                "405623001", "Assigned practitioner",
                loc_id=v_id, loc_display=v_name,
            )
            client.add(role)
            chws.append((p_id, display))
        chw_by_village[v_id] = chws

    print("  Care teams...", flush=True)
    ct_by_sc = {}
    for sc_id, sc_name in subcounty_data:
        org_id, org_name = chw_org_by_sc[sc_id]
        members = []
        for v_id, _, v_sc_id in village_data:
            if v_sc_id == sc_id:
                members.extend(chw_by_village[v_id])
        ct_id, ct = mk_care_team(f"{sc_name} Care Team", org_id, org_name, members[:20])
        client.add(ct)
        ct_by_sc[sc_id] = ct_id

    client.flush()

    return {
        "village_data":    village_data,
        "chw_by_village":  chw_by_village,
        "chw_org_by_sc":   chw_org_by_sc,
        "ct_by_sc":        ct_by_sc,
    }


# ─────────────────────────────────────────────────────────────
# Clinical data for one patient
# ─────────────────────────────────────────────────────────────

def generate_clinical(client, pat_id, gender, age, chw_id, org_id, ct_id, v_id, enroll_date):
    progs = eligible_programs(gender, age)

    if not progs:
        # General household visit — no condition
        enc_id, enc = mk_encounter(pat_id, chw_id, org_id, ct_id, v_id, enroll_date)
        client.add(enc)
        _, obs = mk_observation(pat_id, enc_id, chw_id, org_id, ct_id, v_id, enroll_date)
        client.add(obs)
        _, qr = mk_qr(pat_id, enc_id, None, chw_id, org_id, ct_id, v_id, enroll_date)
        client.add(qr)
        return

    for prog_id in progs:
        prog  = PROG_BY_ID[prog_id]
        dates = encounter_dates(enroll_date, prog["interval_days"], prog["max_encounters"])
        if not dates:
            continue

        # Enrollment encounter + condition
        d0 = dates[0]
        enc_id, enc = mk_encounter(pat_id, chw_id, org_id, ct_id, v_id, d0)
        client.add(enc)
        cond_id, cond = mk_condition(pat_id, enc_id, prog, chw_id, org_id, ct_id, v_id, d0)
        client.add(cond)
        _, obs = mk_observation(pat_id, enc_id, chw_id, org_id, ct_id, v_id, d0)
        client.add(obs)
        _, qr = mk_qr(pat_id, enc_id, prog_id, chw_id, org_id, ct_id, v_id, d0)
        client.add(qr)
        if age < 5:
            _, imm = mk_immunization(pat_id, enc_id, chw_id, org_id, ct_id, v_id, d0)
            client.add(imm)

        # CarePlan + Task for chronic programs
        if prog["chronic"]:
            cp_id, cp = mk_care_plan(pat_id, enc_id, cond_id, prog, chw_id, org_id, ct_id, v_id, d0)
            client.add(cp)
            _, tsk = mk_task(pat_id, cp_id, chw_id, org_id, ct_id, v_id, d0)
            client.add(tsk)

        # Follow-up encounters
        for d in dates[1:]:
            enc_id2, enc2 = mk_encounter(pat_id, chw_id, org_id, ct_id, v_id, d)
            client.add(enc2)
            _, obs2 = mk_observation(pat_id, enc_id2, chw_id, org_id, ct_id, v_id, d)
            client.add(obs2)
            _, qr2 = mk_qr(pat_id, enc_id2, prog_id, chw_id, org_id, ct_id, v_id, d)
            client.add(qr2)
            if age < 5:
                _, imm2 = mk_immunization(pat_id, enc_id2, chw_id, org_id, ct_id, v_id, d)
                client.add(imm2)


# ─────────────────────────────────────────────────────────────
# Patients + households
# ─────────────────────────────────────────────────────────────

def build_patients(client, infra, target_patients):
    village_data   = infra["village_data"]
    chw_by_village = infra["chw_by_village"]
    chw_org_by_sc  = infra["chw_org_by_sc"]
    ct_by_sc       = infra["ct_by_sc"]

    # How many households per village to hit the target
    # Average household: 2 adults + ~2 children = ~4 patients
    hh_per_village = max(1, target_patients // (len(village_data) * 4))

    patients_done = 0

    for v_id, v_name, sc_id in village_data:
        chws     = chw_by_village[v_id]
        org_id, org_name = chw_org_by_sc[sc_id]
        ct_id    = ct_by_sc[sc_id]

        for hh_idx in range(hh_per_village):
            chw_id, _ = chws[hh_idx % len(chws)]

            # Spread enrollment across the data window
            enroll_date = rand_date(DATA_START, DATA_END - timedelta(days=28))

            # Household Group
            surname = random.choice(FAMILY_NAMES)
            hh_id, hh = mk_group(f"{surname} Household", v_id, v_name, chw_id, org_id, ct_id)
            client.add(hh)

            # Head of household
            head_g = random.choice(["male", "female"])
            head_by = DATA_END.year - random.randint(25, 55)
            head_id, head_display, head_res = mk_patient(head_g, head_by, chw_id, org_id, ct_id, v_id, enroll_date)
            client.add(head_res)
            patients_done += 1

            # Spouse
            spouse_g = "female" if head_g == "male" else "male"
            spouse_by = DATA_END.year - random.randint(20, 50)
            spouse_id, spouse_display, spouse_res = mk_patient(spouse_g, spouse_by, chw_id, org_id, ct_id, v_id, enroll_date)
            client.add(spouse_res)
            patients_done += 1

            # RelatedPerson (head ↔ spouse)
            _, rp = mk_related_person(head_id, head_display)
            client.add(rp)

            # Children (1–3)
            for _ in range(random.randint(1, 3)):
                child_g  = random.choice(["male", "female"])
                child_by = DATA_END.year - random.randint(0, 14)
                c_id, _, c_res = mk_patient(child_g, child_by, chw_id, org_id, ct_id, v_id, enroll_date)
                client.add(c_res)
                patients_done += 1
                generate_clinical(client, c_id, child_g, DATA_END.year - child_by,
                                   chw_id, org_id, ct_id, v_id, enroll_date)

            # Clinical data for adults
            generate_clinical(client, head_id,   head_g,   DATA_END.year - head_by,
                               chw_id, org_id, ct_id, v_id, enroll_date)
            generate_clinical(client, spouse_id, spouse_g, DATA_END.year - spouse_by,
                               chw_id, org_id, ct_id, v_id, enroll_date)

        pct = 100.0 * patients_done / target_patients
        print(f"\r  {patients_done:>7,} / ~{target_patients:,} patients  "
              f"({pct:.0f}%)  resources queued: {client.total():,}", end="", flush=True)

    print()


# ─────────────────────────────────────────────────────────────
# The Sengmany family of the SMART Trust demonstrator
#
# Hand-built from input/fsh/examples/people.fsh and j1 to j3 of
# WorldHealthOrganization/smart-trust-demo, which are fictional. SUSHI is not
# needed. The ids are fixed, so loading twice does not duplicate them. The
# household sits in the first village and carries the same meta tags as every
# other record, so the dashboards count it with the rest.
# ─────────────────────────────────────────────────────────────

SNOMED_VACCINE = {
    "hepb":  ("412375000", "Hepatitis B vaccine", "Hep B"),
    "bcg":   ("33490001",  "BCG vaccine",         "BCG"),
    "penta": ("116077000", "Pentavalent vaccine",  "Penta"),
    "opv":   ("396429000", "Oral polio vaccine",   "OPV"),
}

def build_demo_family(client, infra):
    v_id, v_name, sc_id = infra["village_data"][0]
    org_id, _ = infra["chw_org_by_sc"][sc_id]
    ct_id = infra["ct_by_sc"][sc_id]
    chw_id = "trustdemo-vilay"

    client.add({"resourceType": "Practitioner", "id": chw_id, "active": True,
                "name": [{"text": "Vilay", "given": ["Vilay"]}],
                "meta": meta_tags(chw_id, org_id, v_id, ct_id)})
    client.add({"resourceType": "Practitioner", "id": "trustdemo-anan", "active": True,
                "name": [{"text": "Dr Anan", "given": ["Anan"], "prefix": ["Dr"]}]})
    client.add({"resourceType": "Practitioner", "id": "trustdemo-chanthason", "active": True,
                "name": [{"text": "Nurse Chanthason", "given": ["Chanthason"]}]})
    client.add({"resourceType": "Organization", "id": "trustdemo-lomaru-dhc", "active": True,
                "name": "Lomaru District Health Center (demonstrator)"})

    meta = meta_tags(chw_id, org_id, v_id, ct_id)
    start = "2025-10-28"

    def patient(rid, given, gender, birth, extra=None):
        res = {"resourceType": "Patient", "id": rid, "active": True, "gender": gender,
               "birthDate": birth, "deceasedBoolean": False,
               "name": [{"use": "official", "family": "SENGMANY", "given": [given]}],
               "meta": meta,
               "generalPractitioner": [{"reference": f"Practitioner/{chw_id}"}],
               "managingOrganization": {"reference": "Organization/trustdemo-lomaru-dhc"}}
        if extra:
            res.update(extra)
        client.add(res)

    patient("trustdemo-somsak", "Somsak", "male", start,
            {"identifier": [{"system": "http://smart.who.int/trust-demo/sid/onesa-temporary-id",
                              "value": "XXU-TMP-2025-00918"}]})
    patient("trustdemo-khamla", "Khamla", "female", "1999-03-14")
    patient("trustdemo-bounmy", "Bounmy", "male", "1996-08-02")

    for rid, given, gender, code, disp in (
        ("trustdemo-rp-khamla", "Khamla", "female", "MTH", "mother"),
        ("trustdemo-rp-bounmy", "Bounmy", "male",   "FTH", "father")):
        client.add({"resourceType": "RelatedPerson", "id": rid, "active": True,
                    "patient": {"reference": "Patient/trustdemo-somsak", "display": "Somsak SENGMANY"},
                    "relationship": [{"coding": [{"code": code, "display": disp,
                        "system": "http://terminology.hl7.org/CodeSystem/v3-RoleCode"}]}],
                    "name": [{"use": "official", "family": "SENGMANY", "given": [given]}],
                    "gender": gender})

    client.add({"resourceType": "Group", "id": "trustdemo-household", "active": True, "type": "person",
                "actual": True,
                "code": {"coding": [{"code": "35359004", "system": "https://www.snomed.org", "display": "Family"}]},
                "name": "SENGMANY Household", "meta": meta,
                "characteristic": [{"code": {"text": v_name, "coding": [{"code": "hh_location",
                    "system": "http://ona.io/codes", "display": "Household Location"}]}, "exclude": False}],
                "managingEntity": {"reference": f"Organization/{org_id}"},
                "member": [{"entity": {"reference": f"Patient/{p}"}}
                           for p in ("trustdemo-bounmy", "trustdemo-khamla", "trustdemo-somsak")]})

    doses = [  # (id, vaccine, date, performer, place, dose)
        ("trustdemo-imm-hepb-bd", "hepb",  "2025-10-28T09:15:00+07:00", "trustdemo-anan",
         "Kesaro Provincial Hospital, Taifafeki", 1),
        ("trustdemo-imm-bcg-bd",  "bcg",   "2025-10-28T09:20:00+07:00", "trustdemo-anan",
         "Kesaro Provincial Hospital, Taifafeki", 1),
        ("trustdemo-imm-penta-1", "penta", "2026-01-06T10:30:00+07:00", "trustdemo-chanthason",
         "Lomaru District Health Center, Onesa", 1),
        ("trustdemo-imm-opv-1",   "opv",   "2026-01-06T10:32:00+07:00", "trustdemo-chanthason",
         "Lomaru District Health Center, Onesa", 1),
    ]
    for rid, vac, when, who, place, dose in doses:
        code, display, short = SNOMED_VACCINE[vac]
        client.add({"resourceType": "Immunization", "id": rid, "status": "completed",
                    "vaccineCode": {"text": short, "coding": [{"system": FHIR_SNOMED, "code": code, "display": display}]},
                    "patient": {"reference": "Patient/trustdemo-somsak"},
                    "occurrenceDateTime": when, "primarySource": True,
                    "performer": [{"actor": {"reference": f"Practitioner/{who}"}}],
                    "location": {"display": place},
                    "protocolApplied": [{"doseNumberPositiveInt": dose}],
                    "meta": meta})


# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate OHS Player FHIR synthetic test data at scale",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python generate.py                          # 10 k patients against localhost\n"
            "  python generate.py --patients 1000          # quick smoke test\n"
            "  python generate.py --dry-run --patients 100 # count resources only\n"
        ),
    )
    parser.add_argument("--fhir-url",   default="http://localhost:8091/fhir",
                        help="HAPI FHIR base URL")
    parser.add_argument("--patients",   type=int, default=300,
                        help="Target patient count (default: 300)")
    parser.add_argument("--batch-size", type=int, default=500,
                        help="Resources per batch bundle (default: 500)")
    parser.add_argument("--dry-run",    action="store_true",
                        help="Count resources without posting to the server")
    parser.add_argument("--villages",   type=int, default=8,
                        help="Number of villages to generate (default: 8, maximum: all in the list)")
    parser.add_argument("--seed",       type=int, default=42,
                        help="Random seed. The same seed gives the same data (default: 42)")
    parser.add_argument("--no-demo-family", action="store_true",
                        help="Leave out the Sengmany family of the SMART Trust demonstrator")
    args = parser.parse_args()

    if not args.dry_run:
        try:
            resp = requests.get(f"{args.fhir_url}/metadata", timeout=15)
            resp.raise_for_status()
            print(f"Connected to {args.fhir_url}")
        except requests.RequestException as exc:
            print(f"ERROR: Cannot reach {args.fhir_url} — {exc}", file=sys.stderr)
            sys.exit(1)

    random.seed(args.seed)
    del VILLAGE_NAMES[args.villages:]
    client = FHIRClient(args.fhir_url, dry_run=args.dry_run, batch_size=args.batch_size)

    print(f"Generating ~{args.patients:,} patients  "
          f"(data window {DATA_START} → {DATA_END})")
    print("Infrastructure...")
    infra = build_infrastructure(client)

    # The family goes in first and is flushed on its own, so it is on the
    # server even if a later batch fails.
    if not args.no_demo_family:
        print("The Sengmany family (SMART Trust demonstrator)...")
        build_demo_family(client, infra)
        client.flush()

    print("Patients and clinical resources...")
    build_patients(client, infra, args.patients)
    client.flush()

    client.summary()


if __name__ == "__main__":
    main()
