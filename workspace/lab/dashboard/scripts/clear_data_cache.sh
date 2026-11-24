#!/usr/bin/env bash
# Observable Framework keeps each loader's output and only runs a loader again
# when its own file changes. The data changes in the database, not in the
# loader, so the cache is cleared before every build.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf src/.observablehq/cache
