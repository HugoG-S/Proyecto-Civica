-- =============================================================
-- Modelo:      fct_achievement_stats
-- Capa:        Gold - Facts
-- Descripcion: Estadisticas de logros por juego por snapshot.
--              Granularidad: un registro por logro por juego
--              por ejecucion de ingesta.
--              Modelo INCREMENTAL — solo procesa snapshots
--              nuevos desde la ultima ejecucion.
-- Materializacion: incremental
-- Unique key:  stat_key (hash app_id + achievement_name + snapshot_at)
-- Dependencias: stg_steam_players__achievements,
--               int_games_enriched, dim_games, dim_date
-- =============================================================

{{ config(
    materialized='incremental',
    unique_key='stat_key',
    on_schema_change='sync_all_columns'
) }}

WITH achievements AS (

    -- Todos los logros de los snapshots nuevos
    -- El filtro incremental solo trae los que aun no estan en la fact
    SELECT * FROM {{ ref('stg_steam_players__achievements') }}

    {% if is_incremental() %}
    WHERE snapshot_at > (SELECT MAX(snapshot_at) FROM {{ this }})
    {% endif %}

),

games AS (

    -- Atributos del juego — una fila por app_id (la mas reciente)
    -- QUALIFY evita duplicados cuando hay multiples snapshots
    SELECT *
    FROM {{ ref('int_games_enriched') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY app_id
        ORDER BY _loaded_at DESC
    ) = 1

),

dim_games AS (

    -- Solo la version vigente de cada juego (SCD Type 2)
    SELECT * FROM {{ ref('dim_games') }}
    WHERE is_current = true

),

dim_date AS (

    SELECT * FROM {{ ref('dim_date') }}

),

joined AS (

    SELECT
        -- Surrogate key: combinacion unica de juego + logro + momento
        {{ dbt_utils.generate_surrogate_key(['a.app_id', 'a.achievement_name', 'a.snapshot_at']) }}
                                                    AS stat_key,

        -- Claves foraneas a dimensiones
        g.game_key,
        d.date_key,

        -- Atributos del logro
        a.achievement_name,
        a.unlock_pct,
        a.difficulty_label,

        -- Ranking de dificultad dentro del juego
        -- 1 = logro mas dificil (menor unlock_pct)
        -- Permite responder: cual es el logro mas raro de cada juego
        ROW_NUMBER() OVER (
            PARTITION BY a.app_id, a.snapshot_at
            ORDER BY a.unlock_pct ASC
        )                                           AS difficulty_rank,

        a.snapshot_at,
        CURRENT_TIMESTAMP()                         AS _loaded_at

    FROM achievements a
    JOIN games gm
        ON a.app_id = gm.app_id
    LEFT JOIN dim_games g
        ON a.app_id = g.app_id
    LEFT JOIN dim_date d
        ON CAST(TO_CHAR(a.snapshot_at::DATE, 'YYYYMMDD') AS INT) = d.date_key

),

final AS (

    SELECT * FROM joined
    WHERE stat_key IS NOT NULL

)

SELECT * FROM final