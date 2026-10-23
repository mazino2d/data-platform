{#
  Dataset per project and layer.
    prod:       the custom schema alone, e.g. jaffle_shop_staging
    dev and ci: prefixed with the target dataset, e.g. dev_alice_jaffle_shop_staging
                or ci_123_jaffle_shop_staging, so runs never touch prod datasets.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
