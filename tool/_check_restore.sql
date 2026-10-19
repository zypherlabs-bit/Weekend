SELECT 'tables', count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';
SELECT 'functions', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
SELECT 'triggers', count(*) FROM pg_trigger WHERE NOT tgisinternal;
SELECT 'extensions', count(*) FROM pg_extension;
SELECT 'policies', count(*) FROM pg_policies;
SELECT 'profiles_rows', count(*) FROM public.profiles;
SELECT 'spatial_ref_sys_rows', count(*) FROM public.spatial_ref_sys;
SELECT 'public_tables_with_rls', count(*) FROM information_schema.tables t WHERE table_schema='public' AND table_type='BASE TABLE' AND EXISTS (SELECT 1 FROM pg_class c WHERE c.relname=t.table_name AND c.relrowsecurity);