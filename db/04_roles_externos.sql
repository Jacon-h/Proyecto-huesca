-- Usuario de demostración para clientes externos (ASGBD): solo lectura.
-- Es idempotente y no depende del nombre de la base (DB_NAME de .env): se puede repetir sin error.
-- Se ejecuta solo al crear la base (initdb) y, además, cada vez que se lanza ./instalar.sh web.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'resp_demo') THEN
        CREATE ROLE resp_demo LOGIN PASSWORD 'demo_bifi_2026';
    END IF;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO resp_demo', current_database());
END
$$;

GRANT USAGE ON SCHEMA public TO resp_demo;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO resp_demo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO resp_demo;
