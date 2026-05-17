-- =============================================================
-- Modelo:      stg_steam_store__games
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAM_STORE
-- Descripcion: Extrae y limpia la metadata oficial de la
--              Steam Store API. Complementa a stg_steamspy
--              con generos oficiales, categorias, plataformas,
--              idiomas desglosados y precios en EUR.
--              Una fila por juego (registro mas reciente).
-- Materializacion: view
-- Dependencias: source('steam_store', 'raw_steam_store')
-- =============================================================

WITH source AS (

    SELECT * FROM {{ source('steam_store', 'raw_steam_store') }}

),

renamed AS (

    SELECT

        -- Identificacion
        RAW_DATA:steam_appid::NUMBER                        AS app_id,
        RAW_DATA:name::VARCHAR                              AS name,
        RAW_DATA:type::VARCHAR                              AS app_type,

        -- Descripcion
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

        -- Early Access
        -- Steam no tiene un campo booleano directo para Early Access
        -- Lo detectamos comprobando si el genero "Early Access" esta presente
        -- en el array de generos oficiales de Valve
        CASE
            WHEN ARRAY_CONTAINS(
                'Early Access'::VARIANT,
                RAW_DATA:genres::VARIANT
            ) THEN true
            ELSE false
        END                                                 AS is_early_access,

        -- Generos oficiales de Valve
        -- Vienen como array de objetos: [{"id":"1","description":"Action"}]
        -- Se mantiene como VARIANT para desanidar en intermediate
        RAW_DATA:genres::VARIANT                            AS genres_raw,

        -- Categorias funcionales
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

deduped AS (

    -- Paso 3: deduplicacion por app_id
    -- Bronze puede tener multiples filas por juego si se ejecuta
    -- la ingesta varias veces. Nos quedamos solo con la mas reciente.
    SELECT *
    FROM renamed
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY app_id
        ORDER BY _ingested_at DESC
    ) = 1

),

final AS (

    -- Paso 4: filtro de calidad minimo
    -- La CTE final siempre se llama 'final' por convencion dbt
    SELECT * FROM deduped
    WHERE app_id IS NOT NULL

)

SELECT * FROM final