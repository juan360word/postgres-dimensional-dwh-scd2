-- Esquemas del proyecto
-- Vistas limpias sobre el origne -> Staging
-- DWH -> el modelo dimencional (Dimenciones y Hechos)

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dwh;

-- Lo que hace esto es tener una carpeta dentro de la base de datos
-- RECORDAR -> la base de origen viven en public, con esto separamos el origen y si area 