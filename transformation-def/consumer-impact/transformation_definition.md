# Consumer Impact Scan — Transformation Definition

## Objective

Given a source change plan and external impact surface from a prior analysis, scan this consumer repository to find all usages of the changed symbols, APIs, types, and contracts. Determine the impact severity for each usage and describe the exact code change needed. Produce a structured Impact Report.

## Inputs

The user will provide via `additionalPlanContext`:
1. **Source Change Plan**: The full change plan from the source analysis (contents of `SOURCE_CHANGE_PLAN.md`)
2. **External Surface**: The externally-visible changes with searchable symbols
3. **Pre-filter Results**: Files in this consumer repo that matched a grep for the changed symbols (if available)

## Important Context

This is the SECOND phase of a two-phase analysis. The source repository has already been analyzed. Your job is ONLY to scan this consumer repository for impact. Do NOT re-analyze the source change — take the source change plan as given.

If pre-filter results are provided listing specific files that matched, **prioritize analyzing those files first**. They are the most likely to contain relevant usages. Then check for dependency types that grep cannot catch (REST API calls with dynamic URLs, message queue consumers, database queries through ORMs).

---

## Phase 1: Detect Dependency Relationship

Check whether this consumer repository depends on the source repository:

- Scan dependency manifests: `package.json`, `requirements.txt`, `pyproject.toml`, `pom.xml`, `build.gradle`, `go.mod`, `Cargo.toml`, `Gemfile`, or equivalent
- Record the package name, version constraint, and whether the dependency is direct or transitive
- Identify the dependency manifest file and line number

If no package dependency is found, check for:
- Git submodule references
- Vendored/copied code from the source repo
- API-level integration (HTTP calls to endpoints defined in the source repo)
- GraphQL schema files synced from the source repo
- Shared database or message queue contracts
- Shared configuration or environment variables

If NO dependency of any kind is found, produce a short report stating this repo is unimpacted and stop.

## Phase 2: Scan for Usages of Changed Symbols

For each externally-visible change from the source change plan, search this consumer codebase for references. Use these search strategies:

### Direct Code References
- Import/require statements importing the changed symbol
- Function/method calls invoking the changed API
- Type references using the changed interface, type, or class
- Re-exports that surface the changed symbol downstream

### API-Level References
- HTTP client calls hitting changed REST/gRPC endpoints
- GraphQL queries, mutations, or fragments referencing changed fields
- Generated types from GraphQL codegen or OpenAPI generators

### Data Contract References
- Message queue consumers/producers using changed event types or schemas
- Database queries referencing changed tables or columns
- Configuration files using changed config keys or environment variables

### Indirect References
- String-based references in config files, reflection, or dynamic invocation
- Comments and documentation referencing the changed symbols
- Test fixtures and mock data containing the changed values

For each usage found, record:
- **File path** and **line number(s)**
- **Code snippet** showing the usage in context
- **Enclosing function/class/module**
- **Usage type**: `import`, `function_call`, `type_reference`, `inheritance`, `graphql_query`, `graphql_fragment`, `http_call`, `db_query`, `config_ref`, `string_ref`, `re_export`, `test_fixture`, `generated_code`, `message_consumer`, `message_producer`

## Phase 3: Determine Impact per Usage

For each usage, determine:

### Impact Severity
- **Breaking** — will fail to compile, throw runtime error, or produce incorrect results without a code change
- **Behavioral** — will still compile but behavior changes (different defaults, changed semantics)
- **Requires Update** — works today but should be updated to use the new API correctly
- **Requires Regeneration** — auto-generated code that needs to be regenerated (codegen, schema sync)
- **No Impact** — references the symbol but is unaffected by this specific change (e.g., same field name on a different type, comment, unused import)

### Required Code Change
Describe exactly what modification is needed. Be specific:
- "Rename `totalPrice` to `totalGrossAmount` in GraphQL fragment at line 42"
- "Update HTTP endpoint from `/v1/stacks` to `/v2/stacks` at line 87"
- "Add `region` parameter to function call at line 154"
- "Regenerate types by running `npm run codegen` after schema sync"
- "Update message consumer to handle new event schema field"

### Layer Classification
Classify each impact using the same layer taxonomy:
Screen/UI, API, Service Logic, Integration Logic, Database, Configuration, Shared Types, Tests, Documentation

## Phase 4: Produce the Impact Report

Generate an `IMPACT_REPORT.md` file in the repository root with the following structure:

### 4.1 Executive Summary
- Consumer repository name
- Source change request description
- Dependency type and version
- Total usages found
- Severity breakdown: breaking / behavioral / requires update / requires regeneration / no impact
- Key finding (one-paragraph summary of the impact)

### 4.2 Dependency Information
- Package name and version constraint
- Direct or transitive dependency
- Manifest file and line
- Schema version (if applicable)

### 4.3 Impact Summary Table

Group by severity, then by layer:

| File | Line | Layer | Usage Type | Severity | Required Change |
|------|------|-------|-----------|----------|----------------|

### 4.4 Detailed Impact Analysis

For each impacted file, provide:
- Full file path
- All usages found with line numbers and code snippets
- Context (what function/class/module)
- Severity and reasoning
- Exact code change needed

### 4.5 Effort Estimate
- Files requiring manual changes: N
- Files requiring regeneration: N
- Files requiring schema sync: N
- Breaking changes in hand-written code: N
- Estimated effort: Low (1-5 changes) / Medium (6-20) / High (20+)

### 4.6 Migration Recommendations
- Order of operations (what to change first)
- Whether changes can be made before or after the source repo deploys
- Automation possibilities (codegen, find-and-replace, codemods)
- Test files that need updates
- Deployment coordination requirements

### 4.7 Unimpacted Areas
- List files/areas that reference similar symbols but are NOT affected
- Explain why (different type, different context, etc.)
- This prevents false alarms during manual review

### 4.8 Cross-Cutting Concerns
- Re-exports that propagate the change to further downstream consumers
- Coordinated deployment requirements
- Shared infrastructure concerns (databases, queues, config)
