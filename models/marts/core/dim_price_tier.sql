-- =============================================================
-- Modelo:      dim_price_tier
-- Capa:        Gold - Dimensiones
-- Descripcion: Catalogo estatico de segmentos de precio.
--              Define los cinco tiers que se usan en
--              int_games_enriched y fct_game_snapshots.
--              No depende de ninguna fuente de datos externa.
-- Materializacion: table
-- Dependencias: ninguna
-- =============================================================

WITH price_tiers AS (

    SELECT * FROM (VALUES
        (1, 'free',    0.00,  0.00,  1),
        (2, 'budget',  0.01,  4.99,  2),
        (3, 'mid',     5.00,  19.99, 3),
        (4, 'premium', 20.00, 39.99, 4),
        (5, 'aaa',     40.00, NULL,  5)
    ) AS t (price_tier_key, tier_label, min_price_usd, max_price_usd, display_order)

),

final AS (

    SELECT
        price_tier_key,
        tier_label,
        min_price_usd,
        max_price_usd,
        display_order
    FROM price_tiers

)

SELECT * FROM final