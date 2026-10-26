

-- Vistas de staging -> toma el origen,renombra las columnas y deja lo datos
-- Listo para cargar DWH -> Como al ser vistas,siempre reflejan el origen actual

CREATE OR REPLACE VIEW staging.stg_clientes AS 
SELECT
    id AS cliente_id,
    nombre,
    apellido,
    email,
    telefono,
    ciudad,
    departamento,
    segmento,
    fecha_registro
FROM public.clientes;

CREATE OR REPLACE VIEW staging.stg_productos AS
SELECT
    p.id AS producto_id,
    p.sku,
    p.nombre,
    c.nombre AS categoria,
    pr.nombre AS proveedor,
    pr.ciudad AS ciudad_proveedor,
    p.precio_unitario,
    p.costo,
    p.activo
FROM public.productos p
JOIN public.categorias c ON c.id = p.categoria_id
JOIN public.proveedores pr ON pr.id = p.proveedor_id;

-- Sin salario a proposito, esto es un dato sencible entonces no se nececita analisis

CREATE OR REPLACE VIEW staging.stg_empleados AS
SELECT
    id AS empleado_id,
    nombre,
    apellido,
    cargo,
    area,
    fecha_ingreso
FROM public.empleados;

-- Una fila por linea de pedido, (Es el grano de fact_ventas)

CREATE OR REPLACE VIEW staging.stg_ventas AS 
SELECT
    d.id AS detalles_id,
    d.pedido_id,
    p.cliente_id,
    d.producto_id,
    p.empleado_id,
    p.fecha_pedido,
    p.fecha_pedido::date AS fecha,
    p.estado AS estado_pedido,
    p.canal,
    d.cantidad,
    d.precio_unitario,
    d.descuento_pct
FROM public.detalle_pedidos d
JOIN public.pedidos p ON p.id = d.pedido_id

