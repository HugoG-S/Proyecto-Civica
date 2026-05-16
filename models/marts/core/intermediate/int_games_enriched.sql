-- =============================================================
-- Modelo:      int_games_enriched
-- Capa:        Silver - Intermediate
-- Descripcion: Une las tres fuentes de staging por app_id.
--              Primera capa de logica de negocio del proyecto.
--              Base para todas las dimensiones y facts de Gold.
-- Materializacion: view
-- Dependencias: stg_steamspy__games
--               stg_steam_store__games
--               stg_steam_players__snapshots
-- =============================================================

WITH steamspy AS (

    SELECT * FROM {{ ref('stg_steamspy__games') }}

),

store AS (

    SELECT * FROM {{ ref('stg_steam_store__games') }}

),

players AS (

    SELECT * FROM {{ ref('stg_steam_players__snapshots') }}

),

joined AS (

    SELECT
        -- Identificacion
        -- app_id viene de steamspy como fuente principal
        sp.app_id,
        COALESCE(st.name, sp.name)              AS name,
        COALESCE(st.developer, sp.developer)    AS developer,
        COALESCE(st.publisher, sp.publisher)    AS publisher,
        st.app_type,
        st.short_description,

        -- Precio
        -- Usamos Steam Store para EUR y SteamSpy para USD
        sp.price_usd,
        sp.initial_price_usd,
        st.price_eur,
        st.initial_price_eur,
        COALESCE(st.discount_pct, sp.discount_pct)  AS discount_pct,
        COALESCE(st.is_free, sp.price_usd = 0)      AS is_free,

        -- Clasificacion por precio
        -- Segmentamos en tiers para analisis de mercado
        CASE
            WHEN COALESCE(st.is_free, sp.price_usd = 0) THEN 'free'
            WHEN sp.price_usd < 5    THEN 'budget'
            WHEN sp.price_usd < 20   THEN 'mid'
            WHEN sp.price_usd < 40   THEN 'premium'
            ELSE 'aaa'
        END                                         AS price_tier,

        -- Generos y categorias
        -- Generos oficiales de Steam Store (mas fiables que SteamSpy)
        st.genres_raw,
        st.categories_raw,
        sp.genres                                   AS genres_steamspy,
        sp.tags,

        -- Plataformas
        COALESCE(st.platform_windows, false)        AS platform_windows,
        COALESCE(st.platform_mac, false)            AS platform_mac,
        COALESCE(st.platform_linux, false)          AS platform_linux,
        (COALESCE(st.platform_windows, false)
            OR COALESCE(st.platform_mac, false)
            OR COALESCE(st.platform_linux, false))  AS is_multi_platform,

        -- Idiomas
        st.supported_languages_raw,

        -- Fecha de lanzamiento
        st.release_date_raw,
        st.is_coming_soon,

        -- Owners (rango de SteamSpy)
        sp.owners_range,

        -- Parseo del rango de owners a numeros
        -- Formato: "10,000,000 .. 20,000,000"
        TRY_TO_NUMBER(
            REPLACE(SPLIT_PART(sp.owners_range, ' .. ', 1), ',', '')
        )                                           AS owners_min,
        TRY_TO_NUMBER(
            REPLACE(SPLIT_PART(sp.owners_range, ' .. ', 2), ',', '')
        )                                           AS owners_max,

        -- Metricas de reviews
        sp.positive_reviews,
        sp.negative_reviews,
        sp.positive_reviews + sp.negative_reviews   AS total_reviews,
        sp.review_score,

        -- Clasificacion de review score
        CASE
            WHEN sp.review_score >= 0.95 THEN 'Overwhelmingly Positive'
            WHEN sp.review_score >= 0.85 THEN 'Very Positive'
            WHEN sp.review_score >= 0.70 THEN 'Mostly Positive'
            WHEN sp.review_score >= 0.40 THEN 'Mixed'
            WHEN sp.review_score >= 0.20 THEN 'Mostly Negative'
            ELSE 'Overwhelmingly Negative'
        END                                         AS review_score_label,

        -- Metricas de jugadores
        sp.current_players,
        sp.avg_playtime_forever_min,
        sp.avg_playtime_2weeks_min,
        sp.median_playtime_forever_min,
        sp.median_playtime_2weeks_min,

        -- Snapshot
        -- Usamos el snapshot_at de players como timestamp de referencia
        COALESCE(pl.snapshot_at, sp._ingested_at)  AS snapshot_at,

        -- Metadata
        sp._ingested_at,
        CURRENT_TIMESTAMP()                         AS _loaded_at

    FROM steamspy sp
    LEFT JOIN store st
        ON sp.app_id = st.app_id
    LEFT JOIN players pl
        ON sp.app_id = pl.app_id

),

final AS (

    SELECT * FROM joined
    WHERE app_id IS NOT NULL

)

SELECT * FROM final