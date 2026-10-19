#!/bin/sh
echo "### MIGRATIONS (001 FIXED)"
fails=0
for f in $(ls /tmp/migrations/*.sql 2>/dev/null); do
  [ -e "$f" ] || { echo "no mig files"; continue; }
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
echo "### CENSUS"
echo "public tables:            $(psql -tc "SELECT count(*) FROM pg_class c WHERE c.relkind='r' AND c.relnamespace='public'::regnamespace")"
echo "auth+storage+realtime+vault tables: $(psql -tc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname IN ('auth','storage','realtime','vault')")"
echo "user functions (public):  $(psql -tc "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")"
echo "policies:                 $(psql -tc "SELECT count(*) FROM pg_policies")"
echo "tables with RLS:          $(psql -tc "SELECT count(*) FROM pg_class c WHERE c.relkind='r' AND c.relrowsecurity")"
echo "total triggers:           $(psql -tc "SELECT count(*) FROM pg_trigger WHERE tgrelid <> 0")"