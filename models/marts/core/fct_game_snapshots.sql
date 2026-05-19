-- =============================================================
-- Modelo:      fct_game_snapshots
-- Capa:        Gold - Facts
-- Descripcion: Snapshot de metricas por juego por ejecucion
--              de ingesta. Modelo INCREMENTAL — solo procesa
--              registros nuevos con snapshot_at mayor que el
--              maximo ya cargado. Es el ejemplo central del
--              proyecto para demostrar el patron incremental.
-- Materializacion: incremental
-- Unique key:  snapshot_key (hash app_id + snapshot_at)
-- Dependencias: int_games_enriched, dim_games, dim_date,
--               dim_genre, dim_developer, dim_price_tier
-- =============================================================

{{ config(
    materialized='incremental',
    unique_key='snapshot_key',
    on_schema_change='sync_all_columns'
) }}

WITH all_snapshots AS (

    SELECT * FROM {{ ref('stg_steam_players__snapshots') }}

    {% if is_incremental() %}
    WHERE snapshot_at > (SELECT MAX(snapshot_at) FROM {{ this }})
    {% endif %}

),

enriched AS (

    SELECT *
    FROM {{ ref('int_games_enriched') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY app_id
        ORDER BY _loaded_at DESC
    ) = 1

),

joined AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['e.app_id', 's.snapshot_at']) }}
                                                    AS snapshot_key,
        g.game_key,
        d.date_key,
        COALESCE(gn.genre_key,   md5('Unknown'))    AS genre_key,
        COALESCE(dv.developer_key, md5('Unknown'))  AS developer_key,
        COALESCE(pt.price_tier_key, 1)              AS price_tier_key,

        s.current_players,
        e.avg_playtime_2weeks_min,
        e.median_playtime_forever_min,
        e.owners_min,
        e.owners_max,
        IFF(e.owners_min IS NOT NULL AND e.owners_max IS NOT NULL,
            (e.owners_min + e.owners_max) / 2,
            NULL)                                   AS owners_midpoint,
        e.positive_reviews,
        e.negative_reviews,
        e.total_reviews,
        e.review_score,
        e.review_score_label,
        e.price_usd,
        e.price_eur,
        e.discount_pct,
        e.discount_pct > 0                          AS is_on_sale,
        s.snapshot_at,
        CURRENT_TIMESTAMP()                         AS _loaded_at

    FROM all_snapshots s
    JOIN enriched e
        ON s.app_id = e.app_id
    LEFT JOIN {{ ref('dim_games') }} g
        ON e.app_id = g.app_id AND g.is_current = true
    LEFT JOIN {{ ref('dim_date') }} d
        ON CAST(TO_CHAR(s.snapshot_at::DATE, 'YYYYMMDD') AS INT) = d.date_key
    LEFT JOIN {{ ref('dim_genre') }} gn
        ON TRIM(SPLIT_PART(e.genres_steamspy, ',', 1)) = gn.genre_name
    LEFT JOIN {{ ref('dim_developer') }} dv
        ON e.developer = dv.developer_name
    LEFT JOIN {{ ref('dim_price_tier') }} pt
        ON e.price_tier = pt.tier_label

),

final AS (

    SELECT * FROM joined
    WHERE snapshot_key IS NOT NULL

)

SELECT * FROM final