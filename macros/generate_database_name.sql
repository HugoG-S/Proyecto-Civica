{% macro generate_database_name(custom_database_name=none, node=none) -%}

    {%- set default_database = target.database -%}

    {%- if node.fqn[1] == 'marts' and node.fqn[2] != 'intermediate' -%}
        {%- if target.database == 'STEAM_DEV_SILVER' -%}
            STEAM_DEV_GOLD
        {%- elif target.database == 'STEAM_PRO_SILVER' -%}
            STEAM_PRO_GOLD
        {%- else -%}
            {{ default_database }}
        {%- endif -%}
    {%- else -%}
        {{ default_database }}
    {%- endif -%}

{%- endmacro %}