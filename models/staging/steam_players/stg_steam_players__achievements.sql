-- =============================================================
-- Modelo:      stg_steam_players__achievements
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAM_PLAYERS
-- Descripción: Desanida el array de logros del JSON.
--              Una fila por logro por juego por snapshot.
--              Base para fct_achievement_stats en Gold.
-- Materialización: view
-- Dependencias: source('steam_players', 'raw_steam_players')
-- =============================================================

WITH source AS (

    -- Paso 1: leer de Bronze
    SELECT * FROM {{ source('steam_players', 'raw_steam_players') }}

),

flattened AS (

    -- Paso 2: desanidar el array de logros con LATERAL FLATTEN
    -- RAW_DATA:achievements es un array de objetos:
    -- [{"name": "ACH_WIN_ONE_GAME", "percent": 55.3}, ...]
    -- LATERAL FLATTEN crea una fila por cada elemento del array
    SELECT
        s.APPID::NUMBER                             AS app_id,
        s.SNAPSHOT_AT                               AS snapshot_at,
        s.INGESTED_AT                               AS _ingested_at,
        f.value:name::VARCHAR                       AS achievement_name,
        f.value:percent::FLOAT                      AS unlock_pct
    FROM source s,
    LATERAL FLATTEN(
        input => s.RAW_DATA:achievements:achievements
    ) f

),

renamed AS (

    -- Paso 3: añadir campos calculados
    SELECT
        app_id,
        achievement_name,
        unlock_pct,

        -- Clasificación de dificultad basada en unlock_pct
        -- Cuanto menor el porcentaje, más raro y difícil es el logro
        CASE
            WHEN unlock_pct >= 50 THEN 'common'
            WHEN unlock_pct >= 20 THEN 'uncommon'
            WHEN unlock_pct >= 5  THEN 'rare'
            ELSE 'ultra_rare'
        END                                         AS difficulty_label,

        snapshot_at,
        _ingested_at,
        CURRENT_TIMESTAMP()                         AS _loaded_at

    FROM flattened
    -- Solo incluimos juegos que tienen logros
    WHERE achievement_name IS NOT NULL

),

final AS (

    SELECT * FROM renamed
    WHERE app_id IS NOT NULL

)

SELECT * FROM final