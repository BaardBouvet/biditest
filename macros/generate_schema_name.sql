{#
  Override dbt's default schema-name generator.

  By default dbt produces "{target_schema}_{custom_schema}" (e.g.
  "public_staging"), which is safe for shared databases but awkward for
  single-developer projects.  This macro uses the custom schema name directly
  when one is set, matching what most developers expect.

  See: https://docs.getdbt.com/docs/build/custom-schemas
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
