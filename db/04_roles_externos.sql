-- Creación/actualización del usuario de demostración con permisos de solo lectura
CREATE USER resp_demo WITH PASSWORD 'demo_bifi_2026';

-- Conexión a la base de datos mi_base_datos
GRANT CONNECT ON DATABASE mi_base_datos TO resp_demo;
GRANT USAGE ON SCHEMA public TO resp_demo;

-- Permisos de lectura (SELECT) en todas las tablas para resp_demo
GRANT SELECT ON ALL TABLES IN SCHEMA public TO resp_demo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO resp_demo;
