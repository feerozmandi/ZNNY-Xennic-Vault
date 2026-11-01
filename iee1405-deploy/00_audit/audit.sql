-- ═══════════════════════════════════════════════════════════════════════
-- IEE 1405 — پرسش‌های بازرسی PostgreSQL (فقط خواندن)
-- اجرا از طریق 00_audit/audit_postgres.sh
-- هیچ INSERT/UPDATE/DDL ندارد. ایمن برای اجرا روی سامانه زنده.
-- ═══════════════════════════════════════════════════════════════════════
\pset pager off
\pset footer off
\set ON_ERROR_STOP off

\echo '###01|VERSION'
SELECT current_setting('server_version')                     AS pg_version,
       current_setting('server_version_num')                 AS version_num,
       current_database()                                    AS db,
       current_user                                          AS usr,
       inet_server_addr()::text                              AS host,
       inet_server_port()                                    AS port,
       pg_postmaster_start_time()                            AS started_at,
       now() - pg_postmaster_start_time()                    AS uptime;

\echo '###02|EXTENSIONS'
SELECT e.extname, e.extversion, n.nspname AS schema
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
 ORDER BY e.extname;

\echo '###03|AVAILABLE_EXTENSIONS'
SELECT name, default_version, installed_version
  FROM pg_available_extensions
 WHERE name IN ('pg_trgm','pgcrypto','btree_gin','btree_gist','unaccent','uuid-ossp','pg_stat_statements','citext','postgis')
 ORDER BY name;

\echo '###04|DATABASES'
SELECT d.datname,
       pg_catalog.pg_get_userbyid(d.datdba)                AS owner,
       pg_size_pretty(pg_database_size(d.datname))         AS size,
       d.datallowconn,
       d.datconnlimit
  FROM pg_database d
 WHERE NOT d.datistemplate
 ORDER BY pg_database_size(d.datname) DESC;

\echo '###05|ROLES'
SELECT r.rolname,
       r.rolsuper, r.rolcreaterole, r.rolcreatedb,
       r.rolcanlogin, r.rolreplication, r.rolbypassrls,
       r.rolconnlimit,
       r.rolvaliduntil
  FROM pg_roles r
 WHERE r.rolname NOT LIKE 'pg\_%'
 ORDER BY r.rolsuper DESC, r.rolname;

\echo '###06|SCHEMAS'
SELECT n.nspname AS schema,
       pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
       (SELECT count(*) FROM pg_class c WHERE c.relnamespace = n.oid AND c.relkind = 'r') AS tables
  FROM pg_namespace n
 WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
   AND n.nspname NOT LIKE 'pg\_temp%'
 ORDER BY n.nspname;

\echo '###07|TABLE_SIZES'
SELECT schemaname || '.' || relname            AS relation,
       n_live_tup                              AS live_rows,
       n_dead_tup                              AS dead_rows,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
  FROM pg_stat_user_tables
 ORDER BY pg_total_relation_size(relid) DESC
 LIMIT 40;

\echo '###08|EXISTING_IEE_OBJECTS'
SELECT 'table' AS kind, schemaname || '.' || tablename AS obj
  FROM pg_tables
 WHERE schemaname IN ('crm','iee1405','iee_1405','xennic_crm')
UNION ALL
SELECT 'view', schemaname || '.' || viewname FROM pg_views
 WHERE schemaname IN ('crm','iee1405','iee_1405','xennic_crm')
ORDER BY 1, 2;

\echo '###09|N8N_TABLES'
SELECT schemaname || '.' || tablename AS obj,
       n_live_tup AS rows
  FROM pg_tables t JOIN pg_stat_user_tables s
    ON s.schemaname = t.schemaname AND s.relname = t.tablename
 WHERE t.tablename IN ('credentials_entity','workflow_entity','execution_entity','user','settings','migrations')
 ORDER BY 1;

\echo '###10|CONNECTIONS'
SELECT usename, application_name, client_addr::text, state, count(*) AS n,
       max(now() - state_change) AS longest_state
  FROM pg_stat_activity
 WHERE backend_type = 'client backend'
 GROUP BY 1,2,3,4
 ORDER BY n DESC;

\echo '###11|CONNECTION_LIMITS'
SELECT current_setting('max_connections')                     AS max_connections,
       (SELECT count(*) FROM pg_stat_activity)                AS total_backends,
       (SELECT count(*) FROM pg_stat_activity
         WHERE backend_type = 'client backend')               AS client_backends,
       current_setting('superuser_reserved_connections')      AS reserved;

\echo '###12|KEY_SETTINGS'
SELECT name, setting, unit, source
  FROM pg_settings
 WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
                'max_wal_size','wal_level','archive_mode','archive_command',
                'listen_addresses','port','timezone','log_timezone','log_min_duration_statement',
                'password_encryption','ssl','fsync','synchronous_commit','default_text_search_config',
                'autovacuum','max_connections','idle_in_transaction_session_timeout',
                'statement_timeout','row_security')
 ORDER BY name;

\echo '###13|EXT_CONFIG'
SELECT name, setting, source
  FROM pg_settings
 WHERE source = 'configuration file'
 ORDER BY name;

\echo '###14|HBA_FILE'
SELECT current_setting('hba_file') AS hba_file,
       current_setting('config_file') AS config_file,
       current_setting('data_directory') AS data_directory;

\echo '###15|USERS_IN_PUBLIC'
SELECT has_schema_privilege('public','public','CREATE')  AS public_can_create,
       has_schema_privilege('public','public','USAGE')   AS public_can_use,
       current_setting('row_security')                    AS row_security;

\echo '###16|TABLE_PRIVILEGES'
SELECT table_schema || '.' || table_name AS obj, grantee, privilege_type
  FROM information_schema.table_privileges
 WHERE table_schema IN ('public','crm','iee1405')
   AND grantee IN ('PUBLIC','anon','n8n','xennic','wp')
 ORDER BY 1, 2, 3;

\echo '###17|DEFAULT_PRIVILEGES'
SELECT pg_get_userbyid(defaclrole) AS grantor,
       n.nspname AS schema,
       defaclobjtype AS objtype,
       defaclacl::text AS acl
  FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace;

\echo '###18|TABLE_SAMPLE_COLUMNS'
SELECT table_schema || '.' || table_name AS obj, count(*) AS columns
  FROM information_schema.columns
 WHERE table_schema NOT IN ('pg_catalog','information_schema')
 GROUP BY 1 ORDER BY 1;

\echo '###19|LOCKS'
SELECT mode, count(*) AS n
  FROM pg_locks WHERE locktype = 'relation' GROUP BY 1 ORDER BY 2 DESC;

\echo '###20|RECENT_ERRORS'
SELECT datname, count(*) AS n
  FROM pg_stat_database WHERE datname IS NOT NULL GROUP BY 1 ORDER BY 2 DESC;

\echo '###21|BACKUP_CAPABILITY'
SELECT current_setting('archive_mode')   AS archive_mode,
       current_setting('archive_command') AS archive_command,
       (SELECT count(*) FROM pg_stat_archiver) AS archiver_rows;

\echo '###22|DISK_AND_TIME'
SELECT now()                                AS server_now,
       current_setting('TimeZone')          AS server_tz,
       pg_size_pretty(pg_database_size(current_database())) AS db_size;

\echo '###23|N8N_DB_LINK'
SELECT datname, numbackends, xact_commit, xact_rollback,
       stats_reset
  FROM pg_stat_database
 WHERE datname NOT IN ('template0','template1')
 ORDER BY xact_commit DESC;

\echo '###24|END'
SELECT 'audit complete' AS result, now() AS finished_at;
