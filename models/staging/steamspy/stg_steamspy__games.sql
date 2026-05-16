-- =============================================================
-- Modelo:      stg_steamspy__games
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAMSPY_DETAILS
-- Descripción: Extrae y limpia los campos del JSON de SteamSpy.
--              Una fila por juego por snapshot de ingesta.
--              Base para reviews, owners, playtime y tags
--              en capas superiores.
-- Materialización: view
-- Dependencias: source('steamspy', 'raw_steamspy_details')
-- =============================================================

WITH source AS (

    -- Paso 1: leer de Bronze
    -- source() resuelve la ruta usando _steamspy__sources.yml
    SELECT * FROM {{ source('steamspy', 'raw_steamspy_details') }}

),

renamed AS (

    -- Paso 2: extraer campos del VARIANT y tiparlos
    -- La notación RAW_DATA:campo::TIPO extrae el campo del JSON
    -- y lo convierte al tipo de dato correcto de Snowflake
    SELECT

        -- Identificación
        -- app_id es la natural key — el ID de Steam nunca cambia
        RAW_DATA:appid::NUMBER                  AS app_id,
        RAW_DATA:name::VARCHAR                  AS name,
        RAW_DATA:developer::VARCHAR             AS developer,
        RAW_DATA:publisher::VARCHAR             AS publisher,

        -- Precio
        -- SteamSpy devuelve el precio en centavos como string
        -- Ejemplos: "999" = 9.99$ | "0" = Free to Play
        -- Dividimos entre 100 para convertir a dólares
        RAW_DATA:price::NUMBER / 100.0          AS price_usd,
        RAW_DATA:initialprice::NUMBER / 100.0   AS initial_price_usd,
        RAW_DATA:discount::NUMBER               AS discount_pct,

        -- Métricas de jugadores
        -- CCU = Concurrent Users (jugadores activos ahora mismo)
        RAW_DATA:ccu::NUMBER                    AS current_players,
        RAW_DATA:average_forever::NUMBER        AS avg_playtime_forever_min,
        RAW_DATA:average_2weeks::NUMBER         AS avg_playtime_2weeks_min,
        RAW_DATA:median_forever::NUMBER         AS median_playtime_forever_min,
        RAW_DATA:median_2weeks::NUMBER          AS median_playtime_2weeks_min,

        -- Métricas de reviews
        RAW_DATA:positive::NUMBER               AS positive_reviews,
        RAW_DATA:negative::NUMBER               AS negative_reviews,

        -- Review score: positivas / total
        -- IFF evita división por cero si el juego no tiene reviews
        -- Resultado entre 0 y 1 (ej: 0.87 = 87% positivas)
        IFF(
            RAW_DATA:positive::NUMBER + RAW_DATA:negative::NUMBER = 0,
            NULL,
            RAW_DATA:positive::NUMBER /
            (RAW_DATA:positive::NUMBER + RAW_DATA:negative::NUMBER)
        )                                       AS review_score,

        -- Owners
        -- SteamSpy no da cifras exactas, solo rangos
        -- Ejemplo: "10,000,000 .. 20,000,000"
        -- Se parseará en intermediate para obtener min y max
        RAW_DATA:owners::VARCHAR                AS owners_range,

        -- Clasificación
        -- genres viene como string separado por comas
        -- Ejemplo: "Action, Free To Play"
        RAW_DATA:genre::VARCHAR                 AS genres,

        -- languages viene como string separado por comas
        -- Se normalizará en Silver en game_languages
        RAW_DATA:languages::VARCHAR             AS languages,

        -- Tags de comunidad (objeto JSON anidado)
        -- Se mantiene como VARIANT porque es un objeto con N claves
        -- Ejemplo: {"FPS": 91172, "Shooter": 65634, ...}
        -- Se desanidará en intermediate con LATERAL FLATTEN
        RAW_DATA:tags::VARIANT                  AS tags,

        -- Metadata de ingesta
        -- _ingested_at: cuándo llegó el dato a Bronze (viene de Python)
        -- _loaded_at: cuándo lo procesó dbt (ahora mismo)
        INGESTED_AT                             AS _ingested_at,
        CURRENT_TIMESTAMP()                     AS _loaded_at

    FROM source

),

final AS (

    -- Paso 3: filtro de calidad mínimo
    -- Eliminamos filas sin app_id
    -- La CTE final siempre se llama 'final' por convención dbt
    SELECT * FROM renamed
    WHERE app_id IS NOT NULL

)

SELECT * FROM final