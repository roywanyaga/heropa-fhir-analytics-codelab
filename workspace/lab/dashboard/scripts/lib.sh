#!/usr/bin/env bash
# Shared by the data loaders in src/data.
#
# query_or_sample NAME   reads SQL from standard input and prints a CSV.
#
#   LAB_SAMPLE=1   prints sample/NAME instead of asking the database. The lab
#                  sets it when the pipeline has not filled the tables yet.
#   otherwise      runs the SQL against the analytics database. The connection
#                  comes from PGHOST, PGUSER, PGPASSWORD and PGDATABASE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

query_or_sample() {
  local sample="$1"
  if [[ "${LAB_SAMPLE:-0}" == "1" ]]; then
    cat "$ROOT/sample/$sample"
    return
  fi
  psql -X -q -w -v ON_ERROR_STOP=1 --csv -f -
}
