{#
  scd_surrogate_keys(snapshot_ref, id_col, sk_map_ref, mapping_ref)

  Generates three CTEs for SCD snapshot surrogate key derivation.
  Use in staging models that read from a dbt snapshot.

  Args:
    snapshot_ref:  ref() to the snapshot table, e.g. ref('customers_snapshot')
    id_col:        The natural key column in the snapshot, e.g. 'id'
    sk_map_ref:    ref() to the pre-built dim_*_sk_map table.
                   Used on incremental runs for O(1) master_sk lookup.
    mapping_ref:   Optional ref() to an id-mapping table with columns (old_id, new_id).
                   When provided, migrated source IDs resolve to their canonical (original)
                   ID so master_sk stays stable across backend ID migrations.

  Output CTEs (SELECT from _sk_final in your model):
    _sk_base     — snapshot rows normalised: sk, source_id, valid_from, valid_to,
                   is_current, plus all other columns via * EXCEPT (dbt internal cols)
    _sk_resolved — adds canonical_id (= old_id when migrated, else source_id)
    _sk_final    — adds master_sk:
                     incremental run  → map lookup O(1) via sk_map_ref
                     full refresh     → FIRST_VALUE window function (bootstrap only)

  Usage:
    {{ config(materialized='incremental', unique_key='sk', on_schema_change='fail') }}

    WITH
    {{ scd_surrogate_keys(
        ref('customers_snapshot'), 'id',
        sk_map_ref=ref('dim_customer_sk_map'),
        mapping_ref=ref('stg_customer_id_mapping')
    ) }}
    SELECT sk, master_sk, source_id AS customer_id, canonical_id, name, ...
    FROM _sk_final
#}
{% macro scd_surrogate_keys(snapshot_ref, id_col, sk_map_ref=none, mapping_ref=none) %}
_sk_base AS (
    SELECT
        dbt_scd_id                  AS sk,
        {{ id_col }}                AS source_id,
        dbt_valid_from              AS valid_from,
        dbt_valid_to                AS valid_to,
        dbt_valid_to IS NULL        AS is_current,
        * EXCEPT (dbt_scd_id, dbt_updated_at, dbt_valid_from, dbt_valid_to, {{ id_col }})
    FROM {{ snapshot_ref }}
    {% if is_incremental() %}
    -- New versions, plus prior versions the snapshot just closed (dbt_valid_to set).
    -- Without the second branch, closed versions keep valid_to = NULL / is_current = TRUE
    -- in the target, producing overlapping windows and PIT-join fan-out downstream.
    WHERE dbt_valid_from > (SELECT MAX(valid_from) FROM {{ this }})
        OR dbt_valid_to > (SELECT MAX(valid_from) FROM {{ this }})
    {% endif %}
),

_sk_resolved AS (
    SELECT
        b.*,
        {% if mapping_ref is not none %}
        COALESCE(m.old_id, b.source_id)     AS canonical_id
        {% else %}
        b.source_id                          AS canonical_id
        {% endif %}
    FROM _sk_base AS b
    {% if mapping_ref is not none %}
    LEFT JOIN {{ mapping_ref }} AS m ON b.source_id = m.new_id
    {% endif %}
),

_sk_final AS (
    SELECT
        r.*,
        {% if is_incremental() and sk_map_ref is not none %}
        -- Incremental path: hash join against small map table — O(1) per row.
        -- New entities not yet in the map self-assign: COALESCE returns r.sk.
        COALESCE(skm.master_sk, r.sk)        AS master_sk
        {% else %}
        -- Full-refresh path: window function runs once on bootstrap.
        FIRST_VALUE(r.sk) OVER (
            PARTITION BY r.canonical_id
            ORDER BY r.valid_from ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )                                    AS master_sk
        {% endif %}
    FROM _sk_resolved AS r
    {% if is_incremental() and sk_map_ref is not none %}
    LEFT JOIN {{ sk_map_ref }} AS skm ON r.canonical_id = skm.canonical_id
    {% endif %}
)
{% endmacro %}
