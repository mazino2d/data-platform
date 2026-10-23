{#
  scd_sk_map(snapshot_ref, id_col, mapping_ref)

  Generates the full query body for a dim_*_sk_map model.
  Reads directly from the snapshot (NOT via stg_*) to avoid circular dependencies.

  The resulting table has one row per entity (canonical_id → master_sk).
  It is append-only: master_sk never changes once assigned.

  Args:
    snapshot_ref:  ref() to the snapshot table
    id_col:        The natural key column, e.g. 'id'
    mapping_ref:   Optional ref() to id-mapping table (old_id, new_id columns).
                   Needed only for entities where the backend can reassign source IDs.

  Usage:
    {{ config(materialized='incremental', unique_key='canonical_id') }}
    {{ scd_sk_map(ref('customers_snapshot'), 'id', mapping_ref=ref('stg_customer_id_mapping')) }}
#}
{% macro scd_sk_map(snapshot_ref, id_col, mapping_ref=none) %}
WITH _base AS (
    SELECT
        dbt_scd_id      AS sk,
        {{ id_col }}    AS source_id,
        dbt_valid_from  AS valid_from
    FROM {{ snapshot_ref }}
),

_resolved AS (
    SELECT
        b.*,
        {% if mapping_ref is not none %}
        COALESCE(m.old_id, b.source_id)     AS canonical_id
        {% else %}
        b.source_id                          AS canonical_id
        {% endif %}
    FROM _base AS b
    {% if mapping_ref is not none %}
    LEFT JOIN {{ mapping_ref }} AS m ON b.source_id = m.new_id
    {% endif %}
),

_first_version AS (
    -- Keeps the row with the earliest valid_from per canonical_id, which is the
    -- version whose sk becomes the permanent master_sk. BigQuery needs a WHERE
    -- clause next to QUALIFY.
    SELECT canonical_id, sk AS master_sk
    FROM _resolved
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY canonical_id ORDER BY valid_from ASC) = 1
)

SELECT canonical_id, master_sk
FROM _first_version
{% if is_incremental() %}
-- Append-only: skip canonical_ids already in the table.
WHERE canonical_id NOT IN (SELECT canonical_id FROM {{ this }})
{% endif %}
{% endmacro %}
