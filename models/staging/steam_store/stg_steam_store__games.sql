-- =============================================================
-- Modelo:      stg_steam_store__games
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAM_STORE
-- Descripción: Extrae y limpia la metadata oficial de la
--              Steam Store API. Complementa a stg_steamspy
--              con géneros oficiales, categorías, plataformas,
--              idiomas desglosados y precios en EUR.
-- Materialización: view
-- Dependencias: source('steam_store', 'raw_steam_store')
-- =============================================================

WITH source AS (

    -- Paso 1: leer de Bronze
    SELECT * FROM {{ source('steam_store', 'raw_steam_store') }}

),

renamed AS (

    -- Paso 2: extraer campos del VARIANT
    -- La Steam Store API devuelve una estructura más compleja
    -- que SteamSpy — géneros y categorías son arrays de objetos
    SELECT

        -- Identificación
        RAW_DATA:steam_appid::NUMBER                        AS app_id,
        RAW_DATA:name::VARCHAR                              AS name,
        RAW_DATA:type::VARCHAR                              AS app_type,

        -- Descripción
        RAW_DATA:short_description::VARCHAR                 AS short_description,

        -- Desarrollador y publisher
        -- En la Store API vienen como arrays: ["Valve", "Hidden Path"]
        -- Tomamos el primero con [0]
        RAW_DATA:developers[0]::VARCHAR                     AS developer,
        RAW_DATA:publishers[0]::VARCHAR                     AS publisher,

        -- Precio en EUR (consultamos con cc=es)
        -- price_overview es null si el juego es free to play
        RAW_DATA:price_overview:currency::VARCHAR           AS currency,
        RAW_DATA:price_overview:final::NUMBER / 100.0       AS price_eur,
        RAW_DATA:price_overview:initial::NUMBER / 100.0     AS initial_price_eur,
        RAW_DATA:price_overview:discount_percent::NUMBER    AS discount_pct,
        RAW_DATA:is_free::BOOLEAN                           AS is_free,

        -- Fecha de lanzamiento
        -- Viene como objeto: {"coming_soon": false, "date": "21 Aug, 2012"}
        RAW_DATA:release_date:date::VARCHAR                 AS release_date_raw,
        RAW_DATA:release_date:coming_soon::BOOLEAN          AS is_coming_soon,

        -- Géneros oficiales de Valve
        -- Vienen como array de objetos: [{"id":"1","description":"Action"}]
        -- Se mantiene como VARIANT para desanidar en intermediate
        RAW_DATA:genres::VARIANT                            AS genres_raw,

        -- Categorías funcionales
        -- Ejemplos: Single-player, Co-op, Steam Achievements, VR Support
        -- Se mantiene como VARIANT para desanidar en intermediate
        RAW_DATA:categories::VARIANT                        AS categories_raw,

        -- Plataformas soportadas
        -- Viene como objeto: {"windows": true, "mac": false, "linux": false}
        RAW_DATA:platforms:windows::BOOLEAN                 AS platform_windows,
        RAW_DATA:platforms:mac::BOOLEAN                     AS platform_mac,
        RAW_DATA:platforms:linux::BOOLEAN                   AS platform_linux,

        -- Idiomas soportados
        -- Viene como string con formato especial que indica audio
        -- Se mantiene como string para parsear en intermediate
        RAW_DATA:supported_languages::VARCHAR               AS supported_languages_raw,

        -- Website oficial
        RAW_DATA:website::VARCHAR                           AS website,

        -- Metadata de ingesta
        INGESTED_AT                                         AS _ingested_at,
        CURRENT_TIMESTAMP()                                 AS _loaded_at

    FROM source

),

final AS (

    -- Paso 3: filtro de calidad mínimo
    SELECT * FROM renamed
    WHERE app_id IS NOT NULL

)

SELECT * FROM final