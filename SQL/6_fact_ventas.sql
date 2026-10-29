


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



-- Parte B: fact_ventas
-- Grano: una fila por línea de pedido (detalle_pedidos)
-- Llaves foráneas a las dimensiones; métricas calculadas aquí para no repetir lógica en queries

CREATE TABLE IF NOT EXISTS dwh.fact_ventas (
    venta_sk          INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- llaves foráneas a dimensiones
    fecha_sk          INT           NOT NULL REFERENCES dwh.dim_fecha(fecha_sk),
    cliente_sk        INT           NOT NULL REFERENCES dwh.dim_cliente(cliente_sk),
    producto_sk       INT           NOT NULL REFERENCES dwh.dim_producto(producto_sk),
    empleado_sk       INT           NOT NULL REFERENCES dwh.dim_empleado(empleado_sk),
    -- llaves naturales (para trazabilidad al origen)
    pedido_id         INT           NOT NULL,
    detalle_id        INT           NOT NULL,
    -- atributos degenerados (no justifican dimensión propia)
    estado_pedido     VARCHAR(15)   NOT NULL,
    canal             VARCHAR(15)   NOT NULL,
    -- métricas
    cantidad          INT           NOT NULL,
    precio_unitario   NUMERIC(12,2) NOT NULL,
    descuento_pct     NUMERIC(4,1)  NOT NULL DEFAULT 0,
    ingreso_bruto     NUMERIC(14,2) NOT NULL,  -- cantidad * precio_unitario
    descuento_monto   NUMERIC(14,2) NOT NULL,  -- ingreso_bruto * descuento_pct / 100
    ingreso_neto      NUMERIC(14,2) NOT NULL,  -- ingreso_bruto - descuento_monto
    costo_total       NUMERIC(14,2) NOT NULL,  -- cantidad * costo (del producto al momento)
    margen_bruto      NUMERIC(14,2) NOT NULL,  -- ingreso_neto - costo_total

    CONSTRAINT uq_fact_ventas_detalle UNIQUE (detalle_id)
);

CREATE OR REPLACE PROCEDURE dwh.load_fact_ventas()
LANGUAGE plpgsql
AS $$
DECLARE
    v_nuevas INT;
BEGIN
    INSERT INTO dwh.fact_ventas (
        fecha_sk, cliente_sk, producto_sk, empleado_sk,
        pedido_id, detalle_id, estado_pedido, canal,
        cantidad, precio_unitario, descuento_pct,
        ingreso_bruto, descuento_monto, ingreso_neto,
        costo_total, margen_bruto
    )
    SELECT
        f.fecha_sk,
        dc.cliente_sk,
        dp.producto_sk,
        COALESCE(de.empleado_sk, (SELECT empleado_sk FROM dwh.dim_empleado WHERE empleado_id = 0)),
        sv.pedido_id,
        sv.detalles_id,
        sv.estado_pedido,
        sv.canal,
        sv.cantidad,
        sv.precio_unitario,
        sv.descuento_pct,
        sv.cantidad * sv.precio_unitario                                         AS ingreso_bruto,
        sv.cantidad * sv.precio_unitario * sv.descuento_pct / 100                AS descuento_monto,
        sv.cantidad * sv.precio_unitario * (1 - sv.descuento_pct / 100)          AS ingreso_neto,
        sv.cantidad * dp.costo                                                    AS costo_total,
        sv.cantidad * sv.precio_unitario * (1 - sv.descuento_pct / 100)
            - sv.cantidad * dp.costo                                              AS margen_bruto
    FROM staging.stg_ventas sv
    -- dim_fecha: join por la fecha del pedido
    JOIN dwh.dim_fecha f   ON f.fecha = sv.fecha
    -- dim_cliente: versión vigente al momento del pedido (SCD2)
    JOIN dwh.dim_cliente dc
        ON dc.cliente_id = sv.cliente_id
        AND sv.fecha BETWEEN dc.valid_from AND dc.valid_to
    -- dim_producto
    JOIN dwh.dim_producto dp ON dp.producto_id = sv.producto_id
    -- dim_empleado (NULL → miembro especial 0)
    LEFT JOIN dwh.dim_empleado de ON de.empleado_id = sv.empleado_id
    -- solo filas nuevas
    WHERE NOT EXISTS (
        SELECT 1 FROM dwh.fact_ventas fv WHERE fv.detalle_id = sv.detalles_id
    );

    GET DIAGNOSTICS v_nuevas = ROW_COUNT;
    RAISE NOTICE 'fact_ventas: % filas nuevas insertadas', v_nuevas;
END;
$$;

CALL dwh.load_fact_ventas();
