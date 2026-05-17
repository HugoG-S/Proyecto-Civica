-- =============================================================
-- Modelo:      dim_developer
-- Capa:        Gold - Dimensiones
-- Descripcion: Catalogo de desarrolladores extraido de
--              int_games_enriched. Incluye metricas agregadas
--              por developer para analisis de estudio.
-- Materializacion: table
-- Dependencias: int_games_enriched
-- =============================================================

WITH games AS (

    SELECT
        developer,
        publisher,
        genres_steamspy,
        review_score,
        current_players,
        is_free
    FROM {{ ref('int_games_enriched') }}
    WHERE developer IS NOT NULL

),

aggregated AS (

    SELECT
        developer                               AS developer_name,
        MAX(publisher)                          AS publisher_name,
        COUNT(*)                                AS total_games_on_steam,
        AVG(review_score)                       AS avg_review_score,
        SUM(current_players)                    AS total_current_players,
        MAX(CASE WHEN genres_steamspy ILIKE '%Indie%' THEN true
                 ELSE false END)                AS is_indie
    FROM games
    GROUP BY developer

),

final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['developer_name']) }} AS developer_key,
        developer_name,
        publisher_name,
        is_indie,
        total_games_on_steam,
        ROUND(avg_review_score, 3)              AS avg_review_score,
        total_current_players
    FROM aggregated
    ORDER BY total_current_players DESC

)

SELECT * FROM final