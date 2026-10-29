




-- Consultas de negocio sobre el modelo dimensional.
-- Criterio: "ventas" = líneas de pedidos en estado 'entregado'
-- Ejecutar con: make queries


\echo ''
\echo '== 1. Ventas y margen por año y trimestre =='
-- Pregunta: ¿cómo evolucionan ventas y rentabilidad por trimestre?
SELECT d.anio, d.trimestre,
       count(DISTINCT v.pedido_id)                         AS pedidos,
       sum(v.cantidad)                                     AS unidades,
       round(sum(v.ingreso_neto))                                AS ventas,
       round(sum(v.margen_bruto))                              AS margen,
       round(100 * sum(v.margen_bruto) / sum(v.ingreso_neto), 1) AS margen_pct
FROM dwh.fact_ventas v
JOIN dwh.dim_fecha d USING (fecha_sk)
WHERE v.estado_pedido = 'entregado'
GROUP BY d.anio, d.trimestre
ORDER BY d.anio, d.trimestre;

\echo ''
\echo '== 2. Ventas, margen y participación por categoría =='

-- Pregunta: ¿qué categorías venden más y cuáles dejan mejor margen?
-- Concepto: SUM() OVER () calcula el total general para sacar el % de participación


SELECT p.categoria,
       round(sum(v.ingreso_neto))                                   AS ventas,
       round(100 * sum(v.ingreso_neto) / sum(sum(v.ingreso_neto)) OVER (), 1) AS participacion_pct,
       round(100 * sum(v.margen_bruto) / sum(v.ingreso_neto), 1)          AS margen_pct
FROM dwh.fact_ventas v
JOIN dwh.dim_producto p USING (producto_sk)
WHERE v.estado_pedido = 'entregado'
GROUP BY p.categoria
ORDER BY ventas DESC;

\echo ''
\echo '== 3. Top 3 productos por categoría =='

-- Pregunta: ¿cuáles son los productos estrella de cada categoría?

WITH ventas_producto AS (
    SELECT p.categoria, p.nombre AS producto, sum(v.ingreso_neto) AS ventas
    FROM dwh.fact_ventas v
    JOIN dwh.dim_producto p USING (producto_sk)
    WHERE v.estado_pedido = 'entregado'
    GROUP BY p.categoria, p.nombre
), ranking AS (
    SELECT *, RANK() OVER (PARTITION BY categoria ORDER BY ventas DESC) AS posicion
    FROM ventas_producto
)
SELECT categoria, posicion, producto, round(ventas) AS ventas
FROM ranking
WHERE posicion <= 3
ORDER BY categoria, posicion;

\echo ''
\echo '== 4. Evolución mensual: variación vs mes anterior y acumulado del año =='


-- Pregunta: ¿crece o cae la venta mes a mes? ¿cuánto llevamos en el año?
-- Conceptos: LAG() para mirar la fila anterior

WITH mensual AS (
    SELECT d.anio, d.mes, sum(v.ingreso_neto) AS ventas
    FROM dwh.fact_ventas v
    JOIN dwh.dim_fecha d USING (fecha_sk)
    WHERE v.estado_pedido = 'entregado'
    GROUP BY d.anio, d.mes
)
SELECT anio, mes,
       round(ventas)                                                            AS ventas,
       round(LAG(ventas) OVER (ORDER BY anio, mes))                             AS mes_anterior,
       round(100 * (ventas - LAG(ventas) OVER (ORDER BY anio, mes))
                 / NULLIF(LAG(ventas) OVER (ORDER BY anio, mes), 0), 1)         AS variacion_pct,
       round(SUM(ventas) OVER (PARTITION BY anio ORDER BY mes))                 AS acumulado_anio
FROM mensual
ORDER BY anio, mes;

\echo ''
\echo '== 5. Los 2 mejores clientes de cada ciudad (ciudad actual) =='


-- Pregunta -> ¿quiénes son los clientes clave por ciudad?
-- Nota SCD2 -> se suman las ventas por cliente_id (todas sus versiones) y se toma
-- la ciudad de la versión vigente (is_current)


WITH ventas_cliente AS (
    SELECT c.cliente_id, sum(v.ingreso_neto) AS ventas
    FROM dwh.fact_ventas v
    JOIN dwh.dim_cliente c USING (cliente_sk)
    WHERE v.estado_pedido = 'entregado'
    GROUP BY c.cliente_id
), ranking AS (
    SELECT a.ciudad, a.cliente_id, a.nombre || ' ' || a.apellido AS cliente, vc.ventas,
           ROW_NUMBER() OVER (PARTITION BY a.ciudad ORDER BY vc.ventas DESC) AS pos
    FROM ventas_cliente vc
    JOIN dwh.dim_cliente a ON a.cliente_id = vc.cliente_id AND a.is_current
)
SELECT ciudad, pos, cliente, round(ventas) AS ventas
FROM ranking
WHERE pos <= 2
ORDER BY ciudad, pos;

\echo ''
\echo '== 6. SCD2: segmento al comprar vs segmento actual =='


-- Pregunta -> ¿cuánto se vendió a clientes que HOY son Premium pero que
-- cuando compraron eran Regular?
-- Esta consulta SOLO es posible porque dim_cliente guarda historia
-- Con SCD1 solo existiría el segmento de hoy y esta pregunta no se podría responder


SELECT cv.segmento AS segmento_al_comprar,
       ca.segmento AS segmento_actual,
       count(*)                       AS lineas,
       round(sum(v.ingreso_neto))     AS ventas
FROM dwh.fact_ventas v
JOIN dwh.dim_cliente cv ON cv.cliente_sk = v.cliente_sk              -- versión vigente al momento de la compra
JOIN dwh.dim_cliente ca ON ca.cliente_id = cv.cliente_id AND ca.is_current  -- versión de hoy
WHERE v.estado_pedido = 'entregado'
GROUP BY cv.segmento, ca.segmento
ORDER BY cv.segmento, ca.segmento;

\echo ''
\echo '== 7. Cancelaciones y devoluciones por canal =='


-- Pregunta: ¿qué canal tiene más pedidos que se caen?

SELECT canal,
       count(DISTINCT pedido_id)                                              AS pedidos,
       count(DISTINCT pedido_id) FILTER (WHERE estado_pedido = 'cancelado')   AS cancelados,
       count(DISTINCT pedido_id) FILTER (WHERE estado_pedido = 'devuelto')    AS devueltos,
       round(100.0 * count(DISTINCT pedido_id) FILTER (WHERE estado_pedido IN ('cancelado','devuelto'))
             / count(DISTINCT pedido_id), 1)                                  AS pct_perdidos
FROM dwh.fact_ventas
GROUP BY canal
ORDER BY pct_perdidos DESC;

\echo ''
\echo '== 8. Top 5 vendedores =='
-- Pregunta: ¿quién vende más? (se excluye "Sin vendedor": pedidos web/app sin asesor)
SELECT RANK() OVER (ORDER BY sum(v.ingreso_neto) DESC) AS posicion,
       e.nombre || ' ' || e.apellido                   AS vendedor,
       count(DISTINCT v.pedido_id)                     AS pedidos,
       round(sum(v.ingreso_neto))                      AS ventas
FROM dwh.fact_ventas v
JOIN dwh.dim_empleado e USING (empleado_sk)
WHERE v.estado_pedido = 'entregado' AND e.empleado_id <> 0
GROUP BY e.empleado_id, e.nombre, e.apellido
ORDER BY posicion
LIMIT 5;

\echo ''
\echo '== 9. Recompra: ¿cuántos clientes vuelven a comprar? =='


-- Pregunta: ¿qué porcentaje de clientes compra más de una vez?



WITH compras AS (
    SELECT c.cliente_id, count(DISTINCT v.pedido_id) AS n_pedidos
    FROM dwh.fact_ventas v
    JOIN dwh.dim_cliente c USING (cliente_sk)
    WHERE v.estado_pedido = 'entregado'
    GROUP BY c.cliente_id
)
SELECT CASE WHEN n_pedidos = 1 THEN '1 compra'
            WHEN n_pedidos = 2 THEN '2 compras'
            ELSE '3 o más compras' END                          AS tipo_cliente,
       count(*)                                                  AS clientes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)        AS pct
FROM compras
GROUP BY 1
ORDER BY min(n_pedidos);

