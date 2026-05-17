-- =============================================================
-- Modelo:      stg_steam_players__snapshots
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAM_PLAYERS
-- Descripción: Extrae los datos de jugadores activos por juego.
--              Una fila por juego por ejecución de ingesta.
--              Es la base del modelo incremental fct_game_snapshots.
-- Materialización: view
-- Dependencias: source('steam_players', 'raw_steam_players')
-- =============================================================

WITH source AS (

    -- Paso 1: leer de Bronze
    SELECT * FROM {{ source('steam_players', 'raw_steam_players') }}

),

renamed AS (

    -- Paso 2: extraer campos del VARIANT
    SELECT

        -- Identificación
        APPID::NUMBER                                       AS app_id,

        -- Métricas de jugadores
        -- player_count viene ya como columna tipada desde Python
        -- porque lo guardamos explícitamente en el loader
        PLAYER_COUNT::NUMBER                                AS current_players,

        -- Timestamp del snapshot
        -- Es la clave del modelo incremental en Gold
        -- Cada ejecución de Python genera un snapshot_at distinto
        SNAPSHOT_AT                                         AS snapshot_at,

        -- JSON completo por si necesitamos más campos en el futuro
        RAW_DATA:players:player_count::NUMBER               AS player_count_raw,

        -- Metadata de ingesta
        INGESTED_AT                                         AS _ingested_at,
        CURRENT_TIMESTAMP()                                 AS _loaded_at

    FROM source

),

final AS (

    -- Paso 3: filtro de calidad mínimo
    -- Eliminamos filas sin app_id o sin snapshot_at
    SELECT * FROM renamed
    WHERE app_id IS NOT NULL
      AND snapshot_at IS NOT NULL

)

SELECT * FROM final