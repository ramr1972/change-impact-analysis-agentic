# Source Change Analysis — Transformation Definition

## Objective

Given a change request describing a functional update, analyze the source repository to identify every modification needed, classify each change by layer, and separate internal-only changes from externally-visible changes that could impact consumer repositories. Produce two outputs: a full change plan and a machine-readable external impact surface.

## Inputs

The user will provide via `additionalPlanContext`:
1. **Change Request**: A natural-language description of the functionality being changed
2. **Source Repository**: The repo being analyzed (provided as the `-p` path)

---

## Phase 1: Understand the Change Request

Parse the change request and identify:

- What functionality is being modified, added, or removed
- Which components, modules, or services are directly involved
- The intent behind the change (new feature, deprecation, refactor, bug fix, security patch)

## Phase 2: Identify All Required Changes

Walk through the source codebase and produce a detailed list of every modification needed. For each change, record:

- **File path** that needs modification
- **Symbol or component** being changed (function, class, endpoint, schema, config key, UI component)
- **Description** of what needs to change
- **Before/After** summary showing current state and proposed state

## Phase 3: Classify Each Change by Layer

Categorize every change into one or more layers:

| Layer | Description | Examples |
|-------|-------------|---------|
| **Screen / UI** | Frontend components, templates, views, forms | React components, HTML templates, CSS |
| **API** | Public API contracts — REST endpoints, GraphQL schemas, gRPC, SDK signatures | Route definitions, request/response schemas |
| **Service Logic** | Business logic, domain rules, workflows | Service classes, domain models |
| **Integration Logic** | Communication with external systems | API clients, queue publishers, webhook handlers |
| **Database** | Schema changes, migrations, queries, ORM models | DDL scripts, migration files, entity definitions |
| **Configuration** | Environment variables, feature flags, config files, IaC | .env files, YAML configs, CDK templates |
| **Shared Types / Contracts** | Exported types, interfaces, DTOs, protobuf definitions | TypeScript interfaces, OpenAPI specs |
| **Tests** | Test files validating the changed functionality | Unit tests, integration tests, fixtures |
| **Documentation** | Docs, changelogs, migration guides | README updates, CHANGELOG entries |

## Phase 4: Classify Internal vs External Visibility

For each change, determine whether it is **internal-only** or **externally-visible**:

### Externally-Visible Changes (affect consumers)

A change is externally-visible if it modifies something that consumers depend on:

- **GraphQL schema changes**: Field renames, type changes, removed fields, new required arguments
- **REST/gRPC API changes**: Endpoint path changes, request/response schema changes, version changes, removed endpoints
- **Published package exports**: Changed function signatures, renamed exports, modified type definitions in published npm/pip/maven packages
- **Message queue contracts**: Changed event types, topic names, message schemas, queue names
- **Database schema changes**: Table/column renames or removals in shared databases
- **Configuration contracts**: Changed environment variable names, config keys consumed by other services
- **Shared type/interface changes**: Modified DTOs, protobuf definitions, OpenAPI specs shared across repos

### Internal-Only Changes (do NOT affect consumers)

- Private functions, methods, or classes not exported
- Internal refactoring that preserves the public interface
- Test file changes
- Internal documentation
- Implementation details behind a stable API
- UI changes in the source repo's own frontend

## Phase 5: Produce Outputs

Generate TWO files in the repository root:

### File 1: `SOURCE_CHANGE_PLAN.md`

A full human-readable change plan with all changes organized by layer, including before/after details.

Structure:
```markdown
# Source Change Plan

## Change Request
<description>

## Summary
- Total changes: N
- External changes: N
- Internal changes: N

## External Changes (Impact Consumers)

### [Layer] Change description
- File: path/to/file
- Symbol: symbolName
- Before: ...
- After: ...
- External because: <reason why this affects consumers>

## Internal Changes (No Consumer Impact)

### [Layer] Change description
- File: path/to/file
- Symbol: symbolName
- Before: ...
- After: ...
```

### File 2: `EXTERNAL_SURFACE.json`

A machine-readable JSON file listing only the externally-visible changes with searchable symbols. This file will be parsed by automation to pre-filter consumer repos.

Structure:
```json
{
  "change_request": "Description of the change",
  "source_repo": "repo-name",
  "external_changes": [
    {
      "layer": "API",
      "change_type": "graphql_field_rename",
      "description": "Rename Checkout.totalPrice to Checkout.totalGrossAmount",
      "search_symbols": ["totalPrice", "totalGrossAmount", "Checkout"],
      "search_patterns": ["totalPrice", "Checkout.*totalPrice", "checkout.*totalPrice"],
      "file_patterns": ["*.graphql", "*.ts", "*.tsx", "*.js", "*.jsx", "*.py"],
      "before": "totalPrice: TaxedMoney!",
      "after": "totalGrossAmount: TaxedMoney!"
    },
    {
      "layer": "Shared Types",
      "change_type": "type_field_rename",
      "description": "Checkout type totalPrice field renamed",
      "search_symbols": ["totalPrice", "Checkout"],
      "search_patterns": ["totalPrice", "CheckoutFragment", "CheckoutQuery"],
      "file_patterns": ["*.ts", "*.tsx", "*.graphql"],
      "before": "totalPrice: TaxedMoney",
      "after": "totalGrossAmount: TaxedMoney"
    }
  ],
  "all_search_symbols": ["totalPrice", "totalGrossAmount", "Checkout"],
  "dependency_indicators": {
    "package_names": ["saleor", "@saleor/sdk"],
    "api_endpoints": [],
    "queue_topics": [],
    "shared_db_tables": []
  }
}
```

#### Field Definitions for `EXTERNAL_SURFACE.json`:

- **`change_type`**: One of: `graphql_field_rename`, `graphql_field_remove`, `graphql_field_add`, `graphql_type_change`, `rest_endpoint_change`, `rest_schema_change`, `package_export_rename`, `package_export_remove`, `package_export_signature_change`, `type_field_rename`, `type_field_remove`, `type_field_add`, `message_schema_change`, `message_topic_change`, `db_column_rename`, `db_column_remove`, `db_table_rename`, `config_key_change`, `other`
- **`search_symbols`**: Concrete strings to grep for in consumer repos. Include both old and new names.
- **`search_patterns`**: Regex-friendly patterns for more targeted searching.
- **`file_patterns`**: Glob patterns for file types likely to contain references.
- **`dependency_indicators`**: Package names, API endpoints, queue topics, or DB tables that indicate a consumer depends on this source repo.

#### Rules for `all_search_symbols`:
- Include the OLD symbol name (consumers still reference it)
- Include the NEW symbol name (in case consumers have already started migrating)
- Include parent type/class names for context disambiguation
- Keep symbols specific enough to avoid false positives (e.g., `totalPrice` not just `price`)
- For REST APIs, include the endpoint path segments
- For message queues, include topic/queue names and event type strings
