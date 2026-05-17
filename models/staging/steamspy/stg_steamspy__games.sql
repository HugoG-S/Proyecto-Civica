-- =============================================================
-- Modelo:      stg_steamspy__games
-- Capa:        Silver - Staging
-- Fuente:      STEAM_DEV_BRONZE.RAW.RAW_STEAMSPY_DETAILS
-- Descripcion: Extrae y limpia los campos del JSON de SteamSpy.
--              Una fila por juego (registro mas reciente).
--              Base para reviews, owners, playtime y tags
--              en capas superiores.
-- Materializacion: view
-- Dependencias: source('steamspy', 'raw_steamspy_details')
-- =============================================================

WITH source AS (

    -- Paso 1: leer de Bronze
    -- source() resuelve la ruta usando _steamspy__sources.yml
    SELECT * FROM {{ source('steamspy', 'raw_steamspy_details') }}

),

renamed AS (

    -- Paso 2: extraer campos del VARIANT y tiparlos
    SELECT

        -- Identificacion
        -- app_id es la natural key — el ID de Steam nunca cambia
        RAW_DATA:appid::NUMBER                  AS app_id,
        RAW_DATA:name::VARCHAR                  AS name,
        RAW_DATA:developer::VARCHAR             AS developer,
        RAW_DATA:publisher::VARCHAR             AS publisher,

        -- Precio
        -- SteamSpy devuelve el precio en centavos como string
        -- Ejemplos: "999" = 9.99$ | "0" = Free to Play
        -- Dividimos entre 100 para convertir a dolares
        RAW_DATA:price::NUMBER / 100.0          AS price_usd,
        RAW_DATA:initialprice::NUMBER / 100.0   AS initial_price_usd,
        RAW_DATA:discount::NUMBER               AS discount_pct,

        -- Metricas de jugadores
        -- CCU = Concurrent Users (jugadores activos ahora mismo)
        RAW_DATA:ccu::NUMBER                    AS current_players,
        RAW_DATA:average_forever::NUMBER        AS avg_playtime_forever_min,
        RAW_DATA:average_2weeks::NUMBER         AS avg_playtime_2weeks_min,
        RAW_DATA:median_forever::NUMBER         AS median_playtime_forever_min,
        RAW_DATA:median_2weeks::NUMBER          AS median_playtime_2weeks_min,

        -- Metricas de reviews
        RAW_DATA:positive::NUMBER               AS positive_reviews,
        RAW_DATA:negative::NUMBER               AS negative_reviews,

        -- Review score: positivas / total
        -- IFF evita division por cero si el juego no tiene reviews
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
        -- Se parseara en intermediate para obtener min y max
        RAW_DATA:owners::VARCHAR                AS owners_range,

        -- Clasificacion
        -- genres viene como string separado por comas
        RAW_DATA:genre::VARCHAR                 AS genres,

        -- languages viene como string separado por comas
        RAW_DATA:languages::VARCHAR             AS languages,

        -- Tags de comunidad (objeto JSON anidado)
        -- Se mantiene como VARIANT para desanidar en intermediate
        -- con LATERAL FLATTEN
        RAW_DATA:tags::VARIANT                  AS tags,

        -- Metadata de ingesta
        INGESTED_AT                             AS _ingested_at,
        CURRENT_TIMESTAMP()                     AS _loaded_at

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