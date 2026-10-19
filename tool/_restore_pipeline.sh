#!/bin/sh
echo "### MIGRATIONS (fixed 001)"
fails=0
for f in /tmp/migrations/*.sql; do
  out=$(psql -v ON_ERROR_STOP=1 -f "$f" 2>&1)
  rc=$?
  echo "== $f (rc=$rc)"
  echo "$out" | grep -E 'ERROR|FATAL' | sed 's/^/   /'
  [ $rc -ne 0 ] && fails=$((fails+1))
done
echo "migration FAILURES: $fails"
echo "### SCHEMA.DUMP"
out=$(psql -v ON_ERROR_STOP=1 -f /tmp/schema.sql 2>&1)
echo "$out" | grep -E 'ERROR|FATAL' | sed 's/^/   /'
echo "schema dump errors: $(echo "$out" | grep -c ERROR)"
echo "### DATA.DUMP"
out=$(psql -v ON_ERROR_STOP=1 -f /tmp/data.sql 2>&1)
echo "$out" | grep -E 'ERROR|FATAL' | sed 's/^/   /'
echo "data dump errors: $(echo "$out" | grep -c ERROR)"