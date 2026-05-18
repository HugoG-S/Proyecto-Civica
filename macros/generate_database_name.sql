{% macro generate_database_name(custom_database_name=none, node=none) -%}

    {%- set fqn = node.fqn -%}

    {%- if fqn[1] == 'marts' and (fqn | length < 4 or fqn[3] != 'intermediate') -%}
        {%- if 'PRO' in target.schema -%}
            STEAM_PRO_GOLD
        {%- else -%}
            STEAM_DEV_GOLD
        {%- endif -%}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}

{%- endmacro %}