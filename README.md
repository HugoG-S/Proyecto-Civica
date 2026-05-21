# Steam Data Engineering
 
Pipeline de datos end-to-end sobre la plataforma de videojuegos **Steam de Valve**. Extrae datos de tres APIs públicas, los carga en Snowflake y los transforma con dbt Cloud siguiendo arquitectura medallion Bronze → Silver → Gold.
 
## Stack
 
| Herramienta | Uso |
|---|---|
| Python 3.14 | Extracción de APIs e ingesta a Snowflake |
| Snowflake | Data warehouse (formato VARIANT para JSON) |
| dbt Cloud | Transformación SQL (staging → intermediate → marts) |
| Power BI | Visualización y dashboards |
| GitHub | Control de versiones |
 
## Arquitectura
 
```
APIs Steam (Python)
    │
    ▼
BRONZE.RAW               ← JSON crudo en columna VARIANT
    │  dbt staging
    ▼
SILVER.STAGING           ← Extracción, tipado y limpieza de Bronze
    │  dbt intermediate
    ▼
SILVER.INTERMEDIATE      ← Lógica de negocio, joins entre fuentes
    │  dbt marts
    ▼
GOLD.MARTS               ← Modelo dimensional Kimball para BI
```
 
## Capas
 
**Bronze** es la capa de aterrizaje. Python extrae los datos de las tres APIs y los carga directamente en Snowflake como JSON crudo usando el tipo `VARIANT`, sin ninguna transformación. Cada tabla tiene una columna `RAW_DATA` con el payload completo y metadatos de ingesta (`INGESTED_AT`, `SNAPSHOT_AT`). Los datos se cargan en paralelo en los entornos DEV y PRO en cada ejecución.
 
**Silver** se divide en dos subcapas. El staging extrae y tipifica los campos del VARIANT, desanida arrays con `LATERAL FLATTEN`, deduplica con `QUALIFY ROW_NUMBER()` y aplica filtros de calidad mínimos. El intermediate une las tres fuentes de staging por `app_id`, aplica lógica de negocio (price tiers, review score labels, parseo de rangos de owners) y calcula tendencias temporales de jugadores con la función de ventana `LAG`.
 
**Gold** implementa un modelo dimensional Kimball con schema estrella. Cinco dimensiones materializadas como tabla (`dim_games`, `dim_date`, `dim_genre`, `dim_developer`, `dim_price_tier`) y dos tablas de hechos incrementales (`fct_game_snapshots` y `fct_achievement_stats`) que solo procesan los snapshots nuevos en cada ejecución usando la estrategia `merge`.
 
## Fuentes de datos
 
- **SteamSpy API** — owners estimados, reviews, precio USD, CCU, tags de comunidad
- **Steam Store API** — metadata oficial Valve, géneros, plataformas, precio EUR
- **Steam Web API** — jugadores activos en tiempo real, % desbloqueo de logros
## Modelos dbt
 
| Capa | Modelos | Materialización |
|---|---|---|
| Staging | `stg_steamspy__games`, `stg_steam_store__games`, `stg_steam_players__snapshots`, `stg_steam_players__achievements` | view |
| Intermediate | `int_games_enriched`, `int_player_trends` | view |
| Gold dims | `dim_games`, `dim_date`, `dim_genre`, `dim_developer`, `dim_price_tier` | table |
| Gold facts | `fct_game_snapshots`, `fct_achievement_stats` | incremental |
 
```
dbt build → PASS=135  WARN=0  ERROR=0
```
 
## Estructura del repositorio

<img width="381" height="500" alt="Captura de pantalla 2026-05-21 160957" src="https://github.com/user-attachments/assets/62830f4d-675f-49ef-a735-4837b87d23c3" />
<img width="381" height="500" alt="Captura de pantalla 2026-05-21 160931" src="https://github.com/user-attachments/assets/d31bc9d2-fd9c-4bfc-85df-5ddf63ce842d" />

 

## PowerBI

<img width="1410" height="788" alt="Captura de pantalla 2026-05-21 161620" src="https://github.com/user-attachments/assets/504ed682-770d-47e7-b98d-9ed6901dabb3" />
<img width="1434" height="799" alt="Captura de pantalla 2026-05-21 161604" src="https://github.com/user-attachments/assets/a99a82bc-cf3b-40c6-837e-c1a1d1f4b24e" />




## Ejecución rápida
 
```bash
# Ingesta desde APIs
python main.py
 
# Ingesta usando JSONs ya descargados
python main.py --only-load
 
# Transformación completa
dbt build
 
# Solo una capa
dbt build --select tag:staging
```
 
## Entornos DEV → PRO
 
El proyecto mantiene dos entornos completamente separados en Snowflake: **DEV** para desarrollo y **PRO** para producción. Cada entorno tiene sus propias databases (`STEAM_DEV_*` / `STEAM_PRO_*`) y schemas (`DEV_STAGING`, `DEV_INTERMEDIATE`, `DEV_MARTS` / `PRO_*`).
 
El flujo de promoción es el siguiente: se trabaja en la rama `DEV`, se abre un Pull Request hacia `main` en GitHub y, tras el merge, se lanza manualmente el **Job PRO** en dbt Cloud con el comando `dbt build --vars '{"steam_env": "STEAM_PRO"}'`. Las macros `generate_schema_name` y `generate_database_name` se encargan de enrutar cada modelo a la database y schema correctos según el `target.schema` de la conexión activa, sin necesidad de modificar ningún modelo.
 
---
 
*Proyecto Cívica · Data Engineering · Mayo 2026*
