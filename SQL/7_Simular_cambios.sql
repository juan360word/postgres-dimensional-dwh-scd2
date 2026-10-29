


-- El origen no trae historia, así que la creamos: modificamos clientes
-- en fechas del pasado y dejamos que el DWH la registre con SCD2
-- Es repetible -> correrlo otra vez no cambia nada

\echo '=== ANTES: ventas por segmento (segmento del cliente al momento de comprar) ==='
SELECT c.segmento, count(*) AS lineas, round(sum(f.ingreso_neto)) AS ventas_netas
FROM dwh.fact_ventas f
JOIN dwh.dim_cliente c USING (cliente_sk)
GROUP BY c.segmento
ORDER BY c.segmento;


-- Ola 1 (efectiva 2025-07-01): clientes Regular suben a Premium

UPDATE public.clientes
SET    segmento = 'Premium'
WHERE  segmento = 'Regular'
  AND  id % 10 = 0
  AND  fecha_registro < DATE '2025-07-01';

CALL dwh.load_dim_cliente(DATE '2025-07-01');


-- Ola 2 (efectiva 2026-03-01): algunos clientes se mudan a Bogotá (SCD2)
-- y tres clientes cambian de teléfono (SCD1, sin historia)

UPDATE public.clientes
SET    ciudad = 'Bogota', departamento = 'Cundinamarca'
WHERE  id % 15 = 0
  AND  fecha_registro < DATE '2026-03-01'
  AND  ciudad <> 'Bogota';

UPDATE public.clientes SET telefono = '3009999999' WHERE id IN (7, 8, 9);

CALL dwh.load_dim_cliente(DATE '2026-03-01');


-- Recargar hechos para que cada venta apunte a la versión correcta
CALL dwh.load_fact_ventas();

\echo ''
\echo '=== DESPUÉS: ventas por segmento (segmento del cliente al momento de comprar) ==='
SELECT c.segmento, count(*) AS lineas, round(sum(f.ingreso_neto)) AS ventas_netas
FROM dwh.fact_ventas f
JOIN dwh.dim_cliente c USING (cliente_sk)
GROUP BY c.segmento
ORDER BY c.segmento;

\echo ''
\echo '=== Cuántas versiones tiene cada cliente ==='
SELECT versiones, count(*) AS clientes
FROM (SELECT cliente_id, count(*) AS versiones FROM dwh.dim_cliente GROUP BY cliente_id) v
GROUP BY versiones
ORDER BY versiones;

\echo ''
\echo '=== Un cliente cuyas compras quedaron repartidas entre varias versiones ==='
SELECT c.cliente_id, c.segmento, c.ciudad, c.valid_from, c.valid_to, c.is_current,
       count(f.detalle_id) AS lineas_de_venta
FROM dwh.dim_cliente c
LEFT JOIN dwh.fact_ventas f USING (cliente_sk)
WHERE c.cliente_id = (SELECT d.cliente_id
                      FROM dwh.dim_cliente d
                      JOIN dwh.fact_ventas fv USING (cliente_sk)
                      GROUP BY d.cliente_id
                      ORDER BY count(DISTINCT d.cliente_sk) DESC, count(*) DESC, d.cliente_id
                      LIMIT 1)
GROUP BY c.cliente_id, c.segmento, c.ciudad, c.valid_from, c.valid_to, c.is_current
ORDER BY c.valid_from;