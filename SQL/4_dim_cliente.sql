
-- dim_cliente con SCD Tipo 2
-- Atributos con historial (SCD2): ciudad, departamento, segmento
-- Atributos sin historial (SCD1, se sobrescriben): nombre, apellido, email, telefono


CREATE TABLE IF NOT EXISTS dwh.dim_cliente (
    cliente_sk INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(50),
    ciudad VARCHAR(100) NOT NULL,
    departamento VARCHAR(100) NOT NULL,
    segmento VARCHAR(50) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL DEFAULT DATE '9999-12-31',
    is_current BOOLEAN NOT NULL DEFAULT TRUE,


    CONSTRAINT uq_dim_cliente_version UNIQUE (cliente_id, valid_from),
    CONSTRAINT ck_dim_cliente_rango   CHECK (valid_to >= valid_from),
    CONSTRAINT ck_dim_cliente_vigente CHECK (is_current = (valid_to = DATE '9999-12-31'))
);

--- Garantiza qye cada cliente tenga al menos una version vigente

CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_cliente_vigente ON dwh.dim_cliente (cliente_id) WHERE is_current;

CREATE OR REPLACE PROCEDURE dwh.load_dim_cliente(p_fecha_efectiva DATE DEFAULT CURRENT_DATE)
LANGUAGE plpgsql
AS $$
DECLARE
     v_cerradas INT;
    v_nuevas   INT;
    v_scd1     INT;
BEGIN
    -- Cierra la versión vigente de los clientes cuyos atributos SCD2 cambiaron
    UPDATE dwh.dim_cliente d
    SET    valid_to   = p_fecha_efectiva - 1,
           is_current = FALSE
    FROM   staging.stg_clientes s
    WHERE  d.cliente_id = s.cliente_id
      AND  d.is_current
      AND  (d.ciudad, d.departamento, d.segmento)
           IS DISTINCT FROM (s.ciudad, s.departamento, s.segmento);
    GET DIAGNOSTICS v_cerradas = ROW_COUNT;

    --  Inserta la versión vigente de quien no la tiene:
    --    clientes nuevos (desde su fecha de registro) y clientes recién cerrados (desde la fecha efectiva)
    INSERT INTO dwh.dim_cliente
        (cliente_id, nombre, apellido, email, telefono, ciudad, departamento, segmento, valid_from)
    SELECT s.cliente_id, s.nombre, s.apellido, s.email, s.telefono,
           s.ciudad, s.departamento, s.segmento,
           CASE WHEN EXISTS (SELECT 1 FROM dwh.dim_cliente x WHERE x.cliente_id = s.cliente_id)
                THEN p_fecha_efectiva
                ELSE s.fecha_registro
           END
    FROM   staging.stg_clientes s
    WHERE  NOT EXISTS (SELECT 1 FROM dwh.dim_cliente d
                       WHERE d.cliente_id = s.cliente_id AND d.is_current);
    GET DIAGNOSTICS v_nuevas = ROW_COUNT;

    -- 3) SCD1: atributos sin historial se corrigen en todas las versiones del cliente
    UPDATE dwh.dim_cliente d
    SET    nombre = s.nombre, apellido = s.apellido, email = s.email, telefono = s.telefono
    FROM   staging.stg_clientes s
    WHERE  d.cliente_id = s.cliente_id
      AND  (d.nombre, d.apellido, d.email, d.telefono)
           IS DISTINCT FROM (s.nombre, s.apellido, s.email, s.telefono);
    GET DIAGNOSTICS v_scd1 = ROW_COUNT;

    RAISE NOTICE 'dim_cliente: % versiones cerradas, % versiones insertadas, % filas corregidas (SCD1)',
                 v_cerradas, v_nuevas, v_scd1;
END;
$$;

-- Carga inicial (y cualquier recarga: si no hay cambios, no hace nada)
CALL dwh.load_dim_cliente();



