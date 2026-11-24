# Shared by the data loaders in src/data. Observable Framework runs a .sh
# loader with sh, which is dash on Debian and Ubuntu, so this file has to be
# plain POSIX shell. Source it with a dot, not with the word source.
#
# query_or_sample NAME   reads SQL from standard input and prints a CSV.
#
#   LAB_SAMPLE=empty  prints sample/empty/NAME: the right columns and no rows (the
#                  Patients number is 0). The lab builds this before the
#                  pipeline has run, so the dashboard says there is no data yet.
#   LAB_SAMPLE=1   prints sample/NAME, made-up numbers, for working on the
#                  dashboard without a database.
#   otherwise      runs the SQL against the analytics database. The connection
#                  comes from PGHOST, PGUSER, PGPASSWORD and PGDATABASE.
set -eu

# $0 is the loader, in src/data, so the project root is two folders up.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

query_or_sample() {
  case "${LAB_SAMPLE:-0}" in
    1)     cat "$ROOT/sample/$1"; return ;;
    empty) cat "$ROOT/sample/empty/$1"; return ;;
  esac
  psql -X -q -w -v ON_ERROR_STOP=1 --csv -f -
}
