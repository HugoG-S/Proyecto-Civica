WITH snapshots_ranked AS (
    SELECT
        game_key,
        current_players,
        snapshot_at,
        ROW_NUMBER() OVER (PARTITION BY game_key ORDER BY snapshot_at ASC)  AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY game_key ORDER BY snapshot_at DESC) AS rn_last
    FROM {{ ref('fct_game_snapshots') }}
),

first_snap AS (
    SELECT game_key, current_players AS players_first
    FROM snapshots_ranked
    WHERE rn_first = 1
),

last_snap AS (
    SELECT game_key, current_players AS players_last
    FROM snapshots_ranked
    WHERE rn_last = 1
),

joined AS (
    SELECT
        g.name,
        f.players_first,
        l.players_last,
        l.players_last - f.players_first AS delta_absoluto,
        ROUND(
            IFF(f.players_first = 0, NULL,
                (l.players_last - f.players_first) / f.players_first * 100
            ), 1
        )                                AS delta_pct
    FROM first_snap f
    JOIN last_snap l
        ON f.game_key = l.game_key
    JOIN {{ ref('dim_games') }} g
        ON f.game_key = g.game_key
        AND g.is_current = true
)

SELECT *
FROM joined
ORDER BY delta_absoluto DESC