-- =============================================================
-- Modelo:      dim_date
-- Capa:        Gold - Dimensiones
-- Descripcion: Dimension de fechas generada con date_spine.
--              Cubre desde 2020-01-01 hasta 2030-12-31.
--              Permite agrupar por año, trimestre, mes, semana
--              y dia sin calcular nada en la query de BI.
-- Materializacion: table
-- Dependencias: dbt_utils.date_spine
-- =============================================================

WITH date_spine AS (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2020-01-01' as date)",
        end_date="cast('2030-12-31' as date)"
    ) }}

),

final AS (

    SELECT
        CAST(TO_CHAR(date_day, 'YYYYMMDD') AS INT)  AS date_key,
        date_day                                     AS full_date,
        YEAR(date_day)                               AS year,
        QUARTER(date_day)                            AS quarter,
        CONCAT(YEAR(date_day), '-Q', QUARTER(date_day)) AS quarter_label,
        MONTH(date_day)                              AS month,
        MONTHNAME(date_day)                          AS month_name,
        LEFT(MONTHNAME(date_day), 3)                 AS month_short,
        WEEKOFYEAR(date_day)                         AS week,
        DAY(date_day)                                AS day_of_month,
        DAYOFWEEK(date_day)                          AS day_of_week,
        DAYNAME(date_day)                            AS day_name,
        DAYOFWEEK(date_day) IN (1, 7)                AS is_weekend,
        DAYOFWEEK(date_day) NOT IN (1, 7)            AS is_weekday
    FROM date_spine

)

SELECT * FROM final