-- Creación/actualización del usuario de demostración con permisos de solo lectura
CREATE USER resp_demo WITH PASSWORD 'demo_bifi_2026';

-- Conexión a la base de datos bifi
GRANT CONNECT ON DATABASE bifi TO resp_demo;
GRANT USAGE ON SCHEMA public TO resp_demo;

-- Permisos de lectura (SELECT) en todas las tablas para resp_demo
GRANT SELECT ON ALL TABLES IN SCHEMA public TO resp_demo;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO resp_demo;

-- Asegurar que el usuario 'panel' tenga control total CRUD
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO panel;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO panel;
