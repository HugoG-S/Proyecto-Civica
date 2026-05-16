-- =============================================================
-- Modelo:      dim_genre
-- Capa:        Gold - Dimensiones
-- Descripcion: Catalogo de generos unicos extraido de
--              int_games_enriched. Permite analisis por genero
--              sin depender de strings en la fact.
-- Materializacion: table
-- Dependencias: int_games_enriched
-- =============================================================

WITH games AS (

    SELECT
        genres_steamspy,
        genres_raw
    FROM {{ ref('int_games_enriched') }}
    WHERE genres_steamspy IS NOT NULL

),

steamspy_genres AS (

    -- Desanidamos el string de generos de SteamSpy
    -- Formato: "Action, Free To Play, Strategy"
    -- SPLIT crea un array, LATERAL FLATTEN lo convierte en filas
    SELECT DISTINCT
        TRIM(f.value::VARCHAR) AS genre_name
    FROM games g,
    LATERAL FLATTEN(input => SPLIT(g.genres_steamspy, ',')) f
    WHERE TRIM(f.value::VARCHAR) != ''

),

classified AS (

    SELECT
        genre_name,
        CASE
            WHEN genre_name IN ('Free To Play')
                THEN 'monetization_model'
            WHEN genre_name IN ('Early Access')
                THEN 'release_state'
            WHEN genre_name IN ('Massively Multiplayer', 'Racing',
                                'Sports', 'Simulation', 'Strategy',
                                'RPG', 'Action', 'Adventure',
                                'Casual', 'Indie')
                THEN 'core_genre'
            ELSE 'other'
        END AS genre_category

    FROM steamspy_genres

),

final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['genre_name']) }} AS genre_key,
        genre_name,
        genre_category
    FROM classified
    ORDER BY genre_category, genre_name

)

SELECT * FROM final