-- =============================================================
-- Modelo:      int_player_trends
-- Capa:        Silver - Intermediate
-- Descripcion: Prepara las series temporales de jugadores activos.
--              Calcula metricas de tendencia comparando el snapshot
--              actual con el anterior para detectar si un juego
--              esta creciendo o decayendo en popularidad.
-- Materializacion: view
-- Dependencias: stg_steam_players__snapshots
--               stg_steamspy__games
-- =============================================================

WITH snapshots AS (

    SELECT * FROM {{ ref('stg_steam_players__snapshots') }}

),

steamspy AS (

    SELECT
        app_id,
        name,
        avg_playtime_forever_min,
        avg_playtime_2weeks_min,
        median_playtime_forever_min
    FROM {{ ref('stg_steamspy__games') }}

),

with_previous AS (

    SELECT
        s.app_id,
        sp.name,
        s.current_players,
        s.snapshot_at,

        -- Jugadores en el snapshot anterior usando LAG
        -- LAG mira la fila anterior ordenada por snapshot_at
        -- para el mismo app_id
        LAG(s.current_players) OVER (
            PARTITION BY s.app_id
            ORDER BY s.snapshot_at
        )                                           AS previous_players,

        -- Metricas de playtime de SteamSpy
        sp.avg_playtime_forever_min,
        sp.avg_playtime_2weeks_min,
        sp.median_playtime_forever_min,

        s._ingested_at

    FROM snapshots s
    LEFT JOIN steamspy sp ON s.app_id = sp.app_id

),

enriched AS (

    SELECT
        app_id,
        name,
        current_players,
        previous_players,
        snapshot_at,

        -- Diferencia absoluta de jugadores respecto al snapshot anterior
        -- NULL si es el primer snapshot del juego
        current_players - previous_players          AS players_delta,

        -- Variacion porcentual respecto al snapshot anterior
        -- NULL si es el primer snapshot o si previous_players es 0
        IFF(
            previous_players IS NULL OR previous_players = 0,
            NULL,
            (current_players - previous_players) /
            previous_players * 100.0
        )                                           AS players_pct_change,

        -- Etiqueta de tendencia basada en la variacion porcentual
        CASE
            WHEN previous_players IS NULL          THEN 'first_snapshot'
            WHEN players_pct_change >= 10          THEN 'growing'
            WHEN players_pct_change <= -10         THEN 'declining'
            ELSE                                        'stable'
        END                                         AS trend_label,

        -- Metricas de playtime
        avg_playtime_forever_min,
        avg_playtime_2weeks_min,
        median_playtime_forever_min,

        _ingested_at,
        CURRENT_TIMESTAMP()                         AS _loaded_at

    FROM with_previous

),

final AS (

    SELECT * FROM enriched
    WHERE app_id IS NOT NULL

)

SELECT * FROM final