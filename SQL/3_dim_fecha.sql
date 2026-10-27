
-- dim_fecha -> una fila por dia,No existe en el origen entonces se genera
-- Es idempotente -> Se puede correr varias veces sin duplicarce

CREATE TABLE IF NOT EXISTS dwh.dim_fecha(
    fecha_sk INT PRIMARY KEY,
    fecha DATE NOT NULL UNIQUE,
    anio SMALLINT NOT NULL,
    trimestre SMALLINT NOT NULL,
    mes SMALLINT NOT NULL,
    nombre_mes VARCHAR(100) NOT NULL,
    dia SMALLINT NOT NULL,
    dia_semana SMALLINT NOT NULL,
    nombre_dia VARCHAR(100) NOT NULL,
    semana_anio SMALLINT NOT NULL,
    es_fin_de_semana BOOLEAN NOT NULL
);


INSERT INTO dwh.dim_fecha
SELECT
    to_char(d, 'YYYYMMDD')::INT   AS fecha_sk,
    d::date    AS fecha,
    EXTRACT(YEAR    FROM d)::SMALLINT    AS anio,
    EXTRACT(QUARTER FROM d)::SMALLINT    AS trimestre,
    EXTRACT(MONTH   FROM d)::SMALLINT    AS mes,
    (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
           'Agosto','Septiembre','Octubre','Noviembre','Diciembre'])
        [EXTRACT(MONTH FROM d)::INT]   AS nombre_mes,
    EXTRACT(DAY     FROM d)::SMALLINT  AS dia,
    EXTRACT(ISODOW  FROM d)::SMALLINT  AS dia_semana,
    (ARRAY['Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo'])
        [EXTRACT(ISODOW FROM d)::INT]   AS nombre_dia,
    EXTRACT(WEEK    FROM d)::SMALLINT   AS semana_anio,
    EXTRACT(ISODOW  FROM d) IN (6, 7)   AS es_fin_de_semana
FROM generate_series('2023-01-01'::date, '2026-12-31'::date, interval '1 day') AS d
ON CONFLICT (fecha_sk) DO NOTHING;



