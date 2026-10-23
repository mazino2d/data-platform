{% macro snapshot_incremental_filter(snapshot_relation, lookback_days=7) %}

    {%- if model.config.get("invalidate_hard_deletes", false) -%}
        {{ exceptions.raise_compiler_error(
            "snapshot_incremental_filter() cannot be used with invalidate_hard_deletes=true in snapshot '"
            ~ model.name ~ "'. Rows excluded by the WHERE filter would be incorrectly marked as deleted."
        ) }}
    {%- endif -%}

    {%- set relation = adapter.get_relation(
        database=snapshot_relation.database,
        schema=snapshot_relation.schema,
        identifier=snapshot_relation.identifier
    ) -%}

    {%- set updated_at_col = model.config.get("updated_at") -%}

    {%- if relation is not none and updated_at_col -%}
        WHERE {{ updated_at_col }} >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {{ lookback_days }} DAY)
    {%- endif -%}

{% endmacro %}
