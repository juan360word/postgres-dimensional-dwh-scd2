


-- Parte A: dim_empleado (SCD1) + miembro "Sin vendedor"

-- Muchos pedidos (web/app) no tienen vendedor (empleado_id NULL).
-- En vez de dejar la llave nula, se usa un miembro especial con empleado_id = 0.


CREATE TABLE IF NOT EXISTS dwh.dim_empleado (
    empleado_sk INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    empleado_id INT NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    area VARCHAR(100) NOT NULL,
    cargo VARCHAR(100) NOT NULL,
    fecha_ingreso DATE

);


CREATE OR REPLACE PROCEDURE dwh.load_dim_empleado()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Miembro especial para pedidos sin vendedor
    INSERT INTO dwh.dim_empleado(empleado_id,nombre,apellido,cargo,area,fecha_ingreso)
    VALUES (0,'Sin venderdor','N/A','N/A','N/A',NULL)
    ON CONFLICT (empleado_id) DO NOTHING;


    -- SCD1 -> sobre escribe los cambios

    UPDATE dwh.dim_empleado d 
    SET nombre = s.nombre, 
        apellido = s.apellido,
        cargo = s.cargo,
        area = s.area,
        fecha_ingreso = s.fecha_ingreso
    FROM staging.stg_empleados s 
    WHERE d.empleado_id = s.empleado_id
        AND (d.nombre, d.apellido,d.cargo,d.area,d.fecha_ingreso)
            IS DISTINCT FROM (s.nombre,s.apellido,s.cargo,s.area,s.fecha_ingreso);
    
    -- Empleado nuevo

    INSERT INTO dwh.dim_empleado (empleado_id,nombre,apellido,cargo,area,fecha_ingreso)
    SELECT s.empleado_id,s.nombre,s.apellido,s.cargo,s.area,s.fecha_ingreso
    FROM staging.stg_empleados s 
    WHERE NOT EXISTS (SELECT 1 FROM dwh.dim_empleado d WHERE d.empleado_id = s.empleado_id);
END;
$$;

CALL dwh.load_dim_empleado();

