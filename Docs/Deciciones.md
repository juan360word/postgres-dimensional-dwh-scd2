
# Decisiones de diseño

## 1. Grano de fact_ventas
Una fila = una línea de pedido (un producto dentro de un pedido).
Corresponde a una fila de `detalle_pedidos`.

Por qué: es el nivel más detallado. Desde ahí puedo sumar a pedido, cliente,
mes o categoría. Si usara `pedidos` (un pedido = una fila) perdería el
producto, la cantidad y el descuento de cada línea, y no podría analizar
ventas por producto o categoría.

## 2. Dimensiones

| Dimensión | Origen | Notas |
|---|---|---|
| dim_cliente | clientes | SCD2 |
| dim_producto | productos + categorias + proveedores | SCD1; categoría y proveedor se
aplanan en una sola tabla (desnormalizado) |
| dim_fecha | generada con generate_series | no existe en el origen |
| dim_empleado | empleados | vendedor del pedido; puede ser NULL, se mapea a un
miembro "Sin vendedor" |

Atributos que van directo en la tabla de hechos (dimensiones degeneradas):
`pedido_id`, `canal` y `estado_pedido`. Son pocos valores y no tienen
atributos propios, así que no justifican una tabla.

Qué NO entra en esta estrella y por qué:
- `categorias` y `proveedores` no son tablas aparte: se absorben en dim_producto.
- `pagos` y `envios` quedan fuera de fact_ventas. Su grano es distinto
(un pago o envío por pedido, no por línea). Si los metiera en fact_ventas,
el monto del pago se repetiría en cada línea del pedido y al sumar saldría
duplicado. Quedan como posibles `fact_pagos` y `fact_envios` en una
segunda versión.

## 3. Atributos con historial (SCD2) en dim_cliente
- Con historial: `segmento`, `ciudad`, `departamento`.
Cambian en la vida real (un cliente sube a Premium, se muda) y el análisis
histórico debe ver cómo era el cliente al momento de comprar.
- Sin historial (si cambian, solo se corrige): `nombre`, `apellido`, `email`,
`telefono`.

Columnas SCD2: `cliente_sk` (llave sustituta), `cliente_id` (llave natural),
`valid_from`, `valid_to` (9999-12-31 para la versión vigente), `is_current`.
La versión inicial arranca en `fecha_registro` del cliente.

## 4. Medidas de fact_ventas
Del origen:
- `cantidad` (aditiva)
- `precio_unitario` (no aditiva, no se suma)
- `descuento_pct` (no aditiva)

Calculadas al cargar:
- `ingreso_bruto = cantidad * precio_unitario`
- `descuento_monto = ingreso_bruto * descuento_pct / 100`
- `ingreso_neto = ingreso_bruto - descuento_monto`
- `costo_total = cantidad * productos.costo`
- `margen = ingreso_neto - costo_total`

Estas son aditivas y las que se agregan en los reportes.

## 5. Dudas y supuestos
- Se cargan todos los estados de pedido. En las queries de ventas se
filtra a `entregado`; cancelados y devueltos se analizan aparte.
- Como el origen no tiene historial de cambios, se simulan cambios de
segmento y ciudad en `07_simular_cambios.sql`.
- Cada línea de hechos busca la versión del cliente vigente en la
fecha del pedido: `fecha_pedido BETWEEN valid_from AND valid_to`.

