{#
  fk_sk_enrich(source_cte, fk_col, event_time_col, entity_ref, entity_id_col,
               prefix, sk_map_ref, output_cte)

  Enriches an immutable fact CTE with two FK surrogate keys for a referenced entity:
    {prefix}_sk        — version-level: entity version active at event time (PIT join).
                         Use for historical joins and auditing.
    {prefix}_master_sk — entity-level stable key (GROUP BY, COUNT DISTINCT).

  Join strategy (same as fct_orders uses for customer):
    Primary:  entity version whose validity window contains event_time_col.
    Fallback: if no version matches (bootstrap gap), use is_current = TRUE.
    Optional: O(1) master_sk lookup via sk_map_ref as last-resort fallback.

  Args:
    source_cte:      Name of the input CTE to enrich (string, e.g. '_raw').
    fk_col:          FK column name in source_cte (string, e.g. 'order_id').
    event_time_col:  Timestamp column in source_cte for PIT join (string, e.g. 'created_at').
    entity_ref:      ref() to the staging entity model, e.g. ref('stg_orders').
    entity_id_col:   Natural key column in entity model (string, e.g. 'order_id').
    prefix:          Output column prefix (string, e.g. 'order' → order_sk, order_master_sk).
    sk_map_ref:      Optional ref() to dim_*_sk_map for O(1) master_sk fallback.
    output_cte:      Name of the generated output CTE (string, default '_enriched').

  The output CTE contains all columns from source_cte plus {prefix}_sk and {prefix}_master_sk.

  Usage (single enrichment):
    WITH
    _raw AS (SELECT * FROM {{ source("jaffle_shop", "payments") }}),
    {{ fk_sk_enrich('_raw', 'order_id', 'created_at',
                    ref('stg_orders'), 'order_id', 'order',
                    sk_map_ref=ref('dim_order_sk_map'),
                    output_cte='_enriched') }}
    SELECT id AS payment_id, order_id, order_sk, order_master_sk, ...
    FROM _enriched

  Usage (chained — two FK enrichments):
    WITH
    _raw AS (SELECT * FROM {{ source("jaffle_shop", "order_items") }}),
    {{ fk_sk_enrich('_raw', 'order_id', 'created_at',
                    ref('stg_orders'), 'order_id', 'order',
                    sk_map_ref=ref('dim_order_sk_map'), output_cte='_with_order') }},
    {{ fk_sk_enrich('_with_order', 'product_id', 'created_at',
                    ref('stg_products'), 'product_id', 'product',
                    sk_map_ref=ref('dim_product_sk_map'), output_cte='_enriched') }}
    SELECT ..., order_sk, order_master_sk, product_sk, product_master_sk, ...
    FROM _enriched
#}
{% macro fk_sk_enrich(source_cte, fk_col, event_time_col, entity_ref, entity_id_col,
                      prefix, sk_map_ref=none, output_cte='_enriched') %}
{{ output_cte }} AS (
    SELECT
        src.*,
        COALESCE(e_pit_{{ prefix }}.sk, e_cur_{{ prefix }}.sk)
            AS {{ prefix }}_sk,
        COALESCE(
            e_pit_{{ prefix }}.master_sk,
            e_cur_{{ prefix }}.master_sk
            {%- if sk_map_ref is not none -%}
            , skm_{{ prefix }}.master_sk
            {%- endif %}
        )   AS {{ prefix }}_master_sk
    FROM {{ source_cte }} AS src
    -- Primary: entity version active at event time
    LEFT JOIN {{ entity_ref }} AS e_pit_{{ prefix }}
        ON  src.{{ fk_col }} = e_pit_{{ prefix }}.{{ entity_id_col }}
        AND src.{{ event_time_col }} >= e_pit_{{ prefix }}.valid_from
        AND (
            e_pit_{{ prefix }}.valid_to IS NULL
            OR src.{{ event_time_col }} < e_pit_{{ prefix }}.valid_to
        )
    -- Fallback: event precedes first snapshot version (bootstrap gap)
    LEFT JOIN {{ entity_ref }} AS e_cur_{{ prefix }}
        ON  e_pit_{{ prefix }}.sk IS NULL
        AND src.{{ fk_col }} = e_cur_{{ prefix }}.{{ entity_id_col }}
        AND e_cur_{{ prefix }}.is_current = TRUE
    {% if sk_map_ref is not none %}
    -- O(1) master_sk lookup for cases where neither PIT nor fallback resolves
    LEFT JOIN {{ sk_map_ref }} AS skm_{{ prefix }}
        ON src.{{ fk_col }} = skm_{{ prefix }}.canonical_id
    {% endif %}
)
{% endmacro %}
