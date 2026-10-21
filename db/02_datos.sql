--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 16.15 (Debian 16.15-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: inventario; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (1, 'Servidor Web Principal', 4, 'Aula 2', 'Servidor Apache HTTP en Debian para alojamiento del sitio público.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (2, 'Base de Datos PostgreSQL', 7, 'Aula 3', 'Instancia principal de PostgreSQL para almacenamiento de datos.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (3, 'Router Core Sede', 10, 'Aula 4', 'Enrutador principal de frontera para conexión WAN y VLANs.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (4, 'Switch Gestionable L2', 13, 'Aula 1', 'Switch de 24 puertos para interconexión de equipos de oficina.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (5, 'Firewall Perimetral', 16, 'Aula 2', 'Filtro de tráfico y reglas de seguridad de acceso a la red.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (6, 'Servidor DNS Secundario', 19, 'Aula 3', 'Resolución de nombres de dominio interna y de respaldo.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (8, 'Punto de Acceso Wi-Fi 1', 25, 'Aula 1', 'AP inalámbrico para cobertura de red en planta alta.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (9, 'Punto de Acceso Wi-Fi 2', 3, 'Aula 2', 'AP inalámbrico para cobertura de red en zona de recepción.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (10, 'Servidor NAS Almacenamiento', 6, 'Aula 3', 'Sistema de almacenamiento en red para copias de seguridad.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (11, 'Servidor SSH Administración', 9, 'Aula 4', 'Nodo de acceso remoto seguro para administradores.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (12, 'SAI / UPS 1500VA', 12, 'Aula 1', 'Sistema de alimentación ininterrumpida para el rack principal.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (13, 'Proxy Inverso Nginx', 15, 'Aula 2', 'Balanceador de carga y terminación SSL/TLS.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (14, 'Servidor de Monitorización', 18, 'Aula 3', 'Instancia Zabbix/Prometheus para métricas de estado.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (15, 'Impresora de Red', 21, 'Aula 4', 'Equipo multifunción asignado al departamento de administración.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (16, 'Servidor VPN', 24, 'Aula 1', 'Acceso remoto seguro para empleados y teletrabajo.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (17, 'Servidor FTP/SFTP', 2, 'Aula 2', 'Servicio de transferencia segura de archivos internos.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (18, 'Switch PoE Rack 2', 5, 'Aula 3', 'Switch con alimentación PoE para cámaras IP y telefonía.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (19, 'Cámara IP Seguridad', 8, 'Aula 4', 'Videovigilancia del cuarto de servidores y CPD.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (20, 'Panel de Parcheo 48P', 11, 'Aula 1', 'Panel de parcheo Cat6a para organización del cableado.', '2026-09-30 10:10:22.710069');
INSERT INTO public.inventario (id, nombre, cantidad, ubicacion, descripcion, fecha_creacion) VALUES (7, 'Servidor DHCP', 22, 'Aula 4', 'Asignación dinámica de direcciones IP a los clientes.', '2026-09-30 10:10:22.710069');


--
-- Name: inventario_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.inventario_id_seq', 23, true);


--
-- PostgreSQL database dump complete
--


