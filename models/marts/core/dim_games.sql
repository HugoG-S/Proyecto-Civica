-- =============================================================
-- Modelo:      dim_games
-- Capa:        Gold - Dimensiones
-- Descripcion: Dimension principal de juegos.
--              Rastrea cambios historicos en atributos del juego
--              como precio, estado Early Access o nombre.
--              Una fila por version del juego.
-- Materializacion: table
-- Dependencias: int_games_enriched
-- =============================================================

WITH games AS (

    SELECT * FROM {{ ref('int_games_enriched') }}

),

genres_split AS (

    -- Extraemos el genero principal (primero del string)
    -- y todos los generos concatenados limpios
    SELECT
        app_id,
        TRIM(SPLIT_PART(genres_steamspy, ',', 1))   AS primary_genre,
        genres_steamspy                              AS all_genres
    FROM games
    WHERE genres_steamspy IS NOT NULL

),

top_tags AS (

    SELECT
        app_id,
        LISTAGG(key, ', ') WITHIN GROUP (ORDER BY votes DESC) AS top_tags
    FROM (
        SELECT
            g.app_id,
            f.key               AS key,
            f.value::NUMBER     AS votes,
            ROW_NUMBER() OVER (
                PARTITION BY g.app_id
                ORDER BY f.value::NUMBER DESC
            )                   AS rn
        FROM games g,
        LATERAL FLATTEN(input => g.tags) f
        WHERE g.tags IS NOT NULL
    ) ranked
    WHERE rn <= 5
    GROUP BY app_id

),

enriched AS (

    SELECT
        g.app_id,
        g.name,
        g.developer,
        g.publisher,
        COALESCE(gs.primary_genre, 'Unknown')       AS primary_genre,
        COALESCE(gs.all_genres, 'Unknown')          AS all_genres,
        COALESCE(tt.top_tags, '')                   AS top_tags,
        g.platform_windows,
        g.platform_mac,
        g.platform_linux,
        g.is_multi_platform,
        g.is_free,
        g.is_coming_soon,
        g.price_tier,
        g.price_usd,
        g.release_date_raw,
        g.snapshot_at,
        g._loaded_at
    FROM games g
    LEFT JOIN genres_split gs ON g.app_id = gs.app_id
    LEFT JOIN top_tags tt ON g.app_id = tt.app_id

),

final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['app_id']) }}  AS game_key,
        app_id,
        name,
        developer,
        publisher,
        primary_genre,
        all_genres,
        top_tags,
        platform_windows,
        platform_mac,
        platform_linux,
        is_multi_platform,
        is_free,
        is_coming_soon,
        price_tier,
        price_usd,
        release_date_raw,
        snapshot_at                                         AS valid_from,
        NULL::TIMESTAMP_NTZ                                 AS valid_to,
        true                                                AS is_current,
        _loaded_at
    FROM enriched

)

SELECT * FROM final