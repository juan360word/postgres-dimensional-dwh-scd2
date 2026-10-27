

-- dim_producto con SCD Tipo 1 (sin historial: si el dato cambia, se sobrescribe)
-- Categoría y proveedor se aplanan aquí (desnormalización): una sola tabla para filtrar y agrupar.

CREATE TABLE IF NOT EXISTS dwh.dim_producto (
    producto_sk       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- llave sustituta
    producto_id       INT           NOT NULL UNIQUE,                 -- llave natural (la del origen)
    sku               VARCHAR(20)   NOT NULL,
    nombre            VARCHAR(120)  NOT NULL,
    categoria         VARCHAR(60)   NOT NULL,
    proveedor         VARCHAR(100)  NOT NULL,
    ciudad_proveedor  VARCHAR(60)   NOT NULL,
    precio_lista      NUMERIC(12,2) NOT NULL,   -- precio de catálogo actual (el precio real de cada venta va en fact_ventas)
    costo             NUMERIC(12,2) NOT NULL,   -- costo actual del producto
    activo            BOOLEAN       NOT NULL
);

CREATE OR REPLACE PROCEDURE dwh.load_dim_producto()
LANGUAGE plpgsql
AS $$
DECLARE
    v_actualizadas INT;
    v_nuevas       INT;
BEGIN
    -- 1) SCD1: si algo cambió en el origen, se sobrescribe la fila existente
    UPDATE dwh.dim_producto d
    SET    sku = s.sku, nombre = s.nombre, categoria = s.categoria,
           proveedor = s.proveedor, ciudad_proveedor = s.ciudad_proveedor,
           precio_lista = s.precio_unitario, costo = s.costo, activo = s.activo
    FROM   staging.stg_productos s
    WHERE  d.producto_id = s.producto_id
      AND  (d.sku, d.nombre, d.categoria, d.proveedor, d.ciudad_proveedor,
            d.precio_lista, d.costo, d.activo)
           IS DISTINCT FROM
           (s.sku, s.nombre, s.categoria, s.proveedor, s.ciudad_proveedor,
            s.precio_unitario, s.costo, s.activo);
    GET DIAGNOSTICS v_actualizadas = ROW_COUNT;

    -- 2) Productos nuevos
    INSERT INTO dwh.dim_producto
        (producto_id, sku, nombre, categoria, proveedor, ciudad_proveedor, precio_lista, costo, activo)
    SELECT s.producto_id, s.sku, s.nombre, s.categoria, s.proveedor, s.ciudad_proveedor,
           s.precio_unitario, s.costo, s.activo
    FROM   staging.stg_productos s
    WHERE  NOT EXISTS (SELECT 1 FROM dwh.dim_producto d WHERE d.producto_id = s.producto_id);
    GET DIAGNOSTICS v_nuevas = ROW_COUNT;

    RAISE NOTICE 'dim_producto: % filas actualizadas, % filas nuevas', v_actualizadas, v_nuevas;
END;
$$;

CALL dwh.load_dim_producto();






