# 🎮 Steam Data Engineering

> Pipeline de datos de extremo a extremo sobre la plataforma Steam — ingesta con Python, warehouse en Snowflake y transformaciones con dbt siguiendo arquitectura Medallion Bronze / Silver / Gold.

---

## 📐 Arquitectura general

```
┌─────────────────────────────────────────────────────────────────┐
│                        APIs Públicas Steam                       │
│   SteamSpy API   │   Steam Store API   │   Steam Web API        │
└────────┬─────────┴──────────┬──────────┴──────────┬─────────────┘
         │                   │                      │
         └───────────────────▼──────────────────────┘
                      Python · main.py
                   (ingesta + carga a Bronze)
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  BRONZE  │  STEAM_DEV_BRONZE.RAW                                │
│          │  RAW_STEAMSPY_TOP100 · RAW_STEAMSPY_DETAILS          │
│          │  RAW_STEAM_STORE · RAW_STEAM_PLAYERS                 │
│          │  Columna VARIANT — JSON crudo sin tocar              │
└──────────┴────────────────┬────────────────────────────────────┘
                             │  dbt (staging)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  SILVER  │  STEAM_DEV_SILVER                                    │
│          │  DEV_STAGING    — 4 modelos stg_*, vistas            │
│          │  DEV_INTERMEDIATE — 2 modelos int_*, vistas          │
└──────────┴────────────────┬────────────────────────────────────┘
                             │  dbt (marts)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  GOLD    │  STEAM_DEV_GOLD                                      │
│          │  5 dimensiones · 2 facts incrementales               │
│          │  Modelo dimensional listo para BI                    │
└──────────┴─────────────────────────────────────────────────────┘
```

---

## 🗂️ Estructura del repositorio

```
Proyecto-Civica/
│
├── ingesta/                          # Scripts Python de ingesta
│   ├── main.py                       # Punto de entrada principal
│   ├── apis/
│   │   ├── steamspy.py               # SteamSpy API client
│   │   ├── steam_store.py            # Steam Store API client
│   │   └── steam_players.py          # Steam Web API client
│   ├── loaders/
│   │   └── snowflake_loader.py       # Carga a Bronze (VARIANT)
│   └── raw/                          # JSONs locales con timestamp
│
├── models/
│   ├── staging/                      # Extracción y limpieza de Bronze
│   │   ├── steamspy/
│   │   │   ├── _steamspy__sources.yml
│   │   │   ├── _steamspy__models.yml
│   │   │   └── stg_steamspy__games.sql
│   │   ├── steam_store/
│   │   │   ├── _steam_store__sources.yml
│   │   │   ├── _steam_store__models.yml
│   │   │   └── stg_steam_store__games.sql
│   │   └── steam_players/
│   │       ├── _steam_players__sources.yml
│   │       ├── _steam_players__models.yml
│   │       ├── stg_steam_players__snapshots.sql
│   │       └── stg_steam_players__achievements.sql
│   │
│   └── marts/
│       └── core/
│           ├── intermediate/         # Lógica de negocio y joins
│           │   ├── _intermediate__models.yml
│           │   ├── int_games_enriched.sql
│           │   └── int_player_trends.sql
│           │
│           ├── dim_price_tier.sql    # Segmentos de precio (estático)
│           ├── dim_date.sql          # Calendario con dbt_utils.date_spine
│           ├── dim_genre.sql         # Catálogo de géneros únicos
│           ├── dim_developer.sql     # Catálogo de desarrolladores
│           ├── dim_games.sql         # SCD Type 2 — historia de cambios
│           ├── fct_game_snapshots.sql    # INCREMENTAL — estrella del proyecto
│           ├── fct_achievement_stats.sql # INCREMENTAL — logros por juego
│           ├── _core__models.yml     # Tests de Gold (relationships, unique)
│           └── _core__docs.md        # Documentación de Gold
│
├── snapshots/                        # SCD Type 2 gestionado por dbt
├── macros/
├── analyses/
├── seeds/
│
├── dbt_project.yml
└── packages.yml
```

---

## 📦 Fuentes de datos

| Fuente | API | Tabla Bronze | Datos principales |
|--------|-----|-------------|-------------------|
| `steamspy` | steamspy.com/api.php | `RAW_STEAMSPY_TOP100`, `RAW_STEAMSPY_DETAILS` | Owners estimados, reviews, CCU, playtime, tags |
| `steam_store` | store.steampowered.com/api | `RAW_STEAM_STORE` | Géneros, categorías, plataformas, precio EUR |
| `steam_players` | api.steampowered.com | `RAW_STEAM_PLAYERS` | Jugadores activos en tiempo real, % logros |

---

## 🏗️ Modelos dbt

### Silver — Staging (4 modelos · 38 tests ✅)

| Modelo | Fuente Bronze | Noción de fila |
|--------|--------------|----------------|
| `stg_steamspy__games` | `RAW_STEAMSPY_DETAILS` | 1 fila por juego |
| `stg_steam_store__games` | `RAW_STEAM_STORE` | 1 fila por juego |
| `stg_steam_players__snapshots` | `RAW_STEAM_PLAYERS` | 1 fila por juego **por ejecución** |
| `stg_steam_players__achievements` | `RAW_STEAM_PLAYERS` | 1 fila por logro por juego por snapshot |

### Silver — Intermediate (2 modelos · 22 tests ✅)

| Modelo | Descripción |
|--------|-------------|
| `int_games_enriched` | Join de las 3 fuentes, price_tier, review_score_label, owners parseados |
| `int_player_trends` | Series temporales de jugadores con LAG(), players_delta, trend_label |

### Gold — Dimensiones

| Modelo | Materialización | Descripción |
|--------|----------------|-------------|
| `dim_price_tier` | table | Segmentos de precio estáticos (free / budget / mid / premium / aaa) |
| `dim_date` | table | Calendario completo con `dbt_utils.date_spine` |
| `dim_genre` | table | Catálogo de géneros únicos extraído de staging |
| `dim_developer` | table | Catálogo de desarrolladores con is_indie |
| `dim_games` | snapshot (SCD2) | Historia de cambios con valid_from / valid_to / is_current |

### Gold — Facts

| Modelo | Materialización | Granularidad |
|--------|----------------|-------------|
| `fct_game_snapshots` | incremental (merge) | 1 fila por juego por snapshot |
| `fct_achievement_stats` | incremental (merge) | 1 fila por logro por juego por snapshot |

---

## 🛠️ Stack tecnológico

| Herramienta | Uso |
|------------|-----|
| **Python 3.x** | Ingesta desde APIs, carga a Snowflake Bronze |
| **Snowflake** | Data warehouse cloud (warehouse X-Small, role ACCOUNTADMIN) |
| **dbt Cloud** | Transformación de datos (versión stable) |
| **GitHub** | Control de versiones (rama activa: `DEV`) |
| **dbt_utils 1.3.3** | Surrogate keys, date_spine |
| **dbt_date 0.17.2** | Atributos de fecha para dim_date |
| **dbt_expectations 0.10.10** | Tests avanzados de calidad de datos |
| **codegen 0.14.1** | Generación automática de YML |

---

## ⚙️ Configuración de entorno

### Snowflake

```
Account:    XADCEYB-GD75678.snowflakecomputing.com
Warehouse:  WH_CURSO_DATA_ENGINEERING (X-Small)
Role:       ACCOUNTADMIN

Databases:
  STEAM_DEV_BRONZE  →  schema RAW             (datos crudos)
  STEAM_DEV_SILVER  →  DEV_STAGING, DEV_INTERMEDIATE, DEV_MARTS
  STEAM_DEV_GOLD    →  modelo dimensional final
```

### dbt Cloud

```yaml
# dbt_project.yml (extracto)
name: civica_steam
profile: default

models:
  civica_steam:
    staging:
      +materialized: view
      +schema: staging
    marts:
      +materialized: table
      +schema: marts
      core:
        intermediate:
          +materialized: view
          +schema: intermediate
```

### Paquetes (`packages.yml`)

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
  - package: dbt-labs/codegen
    version: [">=0.12.0", "<1.0.0"]
  - package: godatadriven/dbt_date
    version: [">=0.10.0", "<1.0.0"]
  - package: metaplane/dbt_expectations
    version: [">=0.10.0", "<1.0.0"]
```

---

## 🚀 Puesta en marcha

### 1. Ingesta de datos

```bash
# Descarga los 100 juegos del top SteamSpy y carga en Bronze
python main.py --only-load
```

Los JSONs locales quedan en `raw/` con timestamp para auditoría.

### 2. Instalar paquetes dbt

```bash
dbt deps
```

### 3. Ejecutar Silver (staging + intermediate)

```bash
dbt build --select tag:staging tag:intermediate
# Resultado esperado: PASS=88 WARN=0 ERROR=0
```

### 4. Ejecutar Gold completo

```bash
dbt build --select tag:marts
```

### 5. Build completo con tests

```bash
dbt build
```

---

## 🧪 Estrategia de testing

```
Capa           Tests aplicados
──────────────────────────────────────────────────────
Staging        not_null + unique en PK
               (excepción: stg_steam_players__snapshots
               no tiene unique en app_id — múltiples
               filas por juego, una por snapshot)

Intermediate   not_null, accepted_values,
               dbt_expectations para rangos numéricos

Gold dims      unique + not_null en surrogate key
               relationships hacia las facts

Gold facts     unique en surrogate key
               relationships hacia todas las dims
```

---

## 📊 Casos de uso analíticos

- **Análisis de juegos** — géneros con mejor review score, precio vs valoración, free vs pago
- **Tendencias de mercado** — top 100 por propietarios, géneros dominantes, evolución de ventas
- **Comportamiento de jugadores** — evolución de jugadores activos, playtime vs popularidad, logros más difíciles

---

## 📋 Convenciones del proyecto

### Nomenclatura

| Capa | Patrón |
|------|--------|
| Staging | `stg_<source>__<entity>.sql` |
| Intermediate | `int_<entity>_<verb>.sql` |
| Dimensiones | `dim_<entity>.sql` |
| Facts | `fct_<process>.sql` |
| Snapshots SCD2 | `<entity>_snapshot.sql` |

- CTE final siempre llamada `final` → `SELECT * FROM final` al cierre de cada modelo
- Doble guión bajo entre source y entidad en staging
- Rama activa en GitHub: `DEV` — nunca trabajar directamente en `main`

### Gotchas descubiertos

- No usar `{{ }}` dentro de comentarios SQL — dbt los interpreta como Jinja
- Usar dbt **stable**, no Fusion preview (bugs con comentarios y sintaxis de tests)
- Tests de `dbt_expectations`: sintaxis directa `min_value: 0` sin wrapper `arguments:`
- Paquetes: `godatadriven/dbt_date` y `metaplane/dbt_expectations` (los nombres `calogica/` están deprecados)
- `executemany` con `PARSE_JSON()` no funciona en `snowflake-connector-python >= 4.x` — usar bucle `for` con `cursor.execute()` individual

---

## 📁 Documentación generada

| Documento | Contenido |
|-----------|-----------|
| `documentacion_staging_steam.docx` | Staging completo documentado |
| `documentacion_silver_steam.docx` | Silver completo (staging + intermediate) |
| `steam_silver_erm.dbml` | Modelo entidad-relación Silver para dbdiagram.io |
| `steam_gold_dimensional.dbml` | Modelo dimensional Gold para dbdiagram.io |
| `resumen_proyecto_steam.md` | Resumen ejecutivo del proyecto |
| `conceptos_clave_proyecto.md` | Glosario para defender el proyecto |
| `guia_ingesta_steam.md` | Guía completa de los scripts Python |

---

## 🔭 Roadmap

- [x] Ingesta Python desde 3 APIs de Steam
- [x] Carga Bronze en Snowflake (columna VARIANT)
- [x] Staging — 4 modelos, 38 tests
- [x] Intermediate — 2 modelos, 22 tests
- [ ] Gold — 5 dimensiones
- [ ] Gold — 2 facts incrementales
- [ ] Tests de relaciones en `_core__models.yml`
- [ ] Segunda ejecución de ingesta (demo de incrementales)
- [ ] Documentación Word de Gold
- [ ] Commit de rama DEV a GitHub

---

<p align="center">
  Proyecto de Data Engineering · Mayo 2026
</p>
