# Consolidated Change Impact Analysis Report

**Date:** 2026-04-27 13:30:21
**Source Repository:** saleor
**Change Request:** # Change Request: Rename totalPrice to totalGrossAmount in Checkout Type
**Consumer Repos Scanned:** 6
**Succeeded:** 4 | **Failed:** 0 | **Clone Failed:** 0

---

## Source Change Plan

# Source Change Plan

## Change Request

Rename the `totalPrice` field to `totalGrossAmount` on the `Checkout` GraphQL type in the Saleor core API. This is a **breaking change** to the GraphQL schema.

- **Target type**: `Checkout` (GraphQL type)
- **Current field name**: `totalPrice`
- **New field name**: `totalGrossAmount`
- **Scope**: Only the `Checkout` type is affected. `CheckoutLine.totalPrice`, `OrderLine.totalPrice`, and all other types with `totalPrice` fields are **NOT** in scope.

## Summary

- **Total changes**: 5 (categories)
- **External changes**: 2
- **Internal changes**: 3 (categories covering ~170 test/fixture files)

---

## External Changes (Impact Consumers)

### [API] Rename `total_price` field to `total_gross_amount` on the Checkout GraphQL type

- **File**: `saleor/graphql/checkout/types.py`
- **Symbol**: `Checkout.total_price` (GraphQL field definition, ~line 805)
- **Description**: The field definition on the `Checkout` GraphQL type must be renamed from `total_price` to `total_gross_amount`. Graphene converts Python snake_case field names to camelCase in the GraphQL schema, so `total_price` becomes `totalPrice` and `total_gross_amount` will become `totalGrossAmount`.
- **Before**:
  ```python
  total_price = BaseField(
      TaxedMoney,
      description=(
          "The sum of the checkout line prices, with all the taxes,"
          "shipping costs, and discounts included."
      ),
      required=True,
      webhook_events_info=[
          WebhookEventInfo(
              type=WebhookEventSyncType.CHECKOUT_CALCULATE_TAXES,
              description=CHECKOUT_CALCULATE_TAXES_MESSAGE,
          ),
      ],
  )
  ```
- **After**:
  ```python
  total_gross_amount = BaseField(
      TaxedMoney,
      description=(
          "The sum of the checkout line prices, with all the taxes,"
          "shipping costs, and discounts included."
      ),
      required=True,
      webhook_events_info=[
          WebhookEventInfo(
              type=WebhookEventSyncType.CHECKOUT_CALCULATE_TAXES,
              description=CHECKOUT_CALCULATE_TAXES_MESSAGE,
          ),
      ],
  )
  ```
- **External because**: This directly changes the GraphQL schema field name from `totalPrice` to `totalGrossAmount` on the `Checkout` type. Any consumer querying `checkout { totalPrice { ... } }` will get a schema validation error.

---

### [Shared Types / Contracts] Update `schema.graphql` for Checkout type

- **File**: `saleor/graphql/schema.graphql`
- **Symbol**: `Checkout.totalPrice` (line 3760)
- **Description**: The generated schema file must reflect the renamed field.
- **Before**:
  ```graphql
  totalPrice: TaxedMoney! @webhookEventsInfo(asyncEvents: [], syncEvents: [CHECKOUT_CALCULATE_TAXES])
  ```
- **After**:
  ```graphql
  totalGrossAmount: TaxedMoney! @webhookEventsInfo(asyncEvents: [], syncEvents: [CHECKOUT_CALCULATE_TAXES])
  ```
- **External because**: This is the canonical GraphQL schema definition. Consumer SDKs, code generators, and GraphQL clients validate queries against this schema. The field rename will break any query referencing `totalPrice` on the `Checkout` type.

---

## Internal Changes (No Consumer Impact)

### [Service Logic] Rename resolver method `resolve_total_price` → `resolve_total_gross_amount`

- **File**: `saleor/graphql/checkout/types.py`
- **Symbol**: `Checkout.resolve_total_price` (~line 1013)
- **Description**: Graphene resolvers follow the convention `resolve_<field_name>`. When the field is renamed from `total_price` to `total_gross_amount`, the resolver must be renamed accordingly. The resolver logic itself (reading from `checkout_info.checkout.total` and computing gift card deductions) does NOT change.
- **Before**:
  ```python
  @staticmethod
  @traced_resolver
  @prevent_sync_event_circular_query
  def resolve_total_price(
      root: SyncWebhookControlContext[models.Checkout], info: ResolveInfo
  ):
      ...
  ```
- **After**:
  ```python
  @staticmethod
  @traced_resolver
  @prevent_sync_event_circular_query
  def resolve_total_gross_amount(
      root: SyncWebhookControlContext[models.Checkout], info: ResolveInfo
  ):
      ...
  ```

---

### [Tests] Update all GraphQL query strings and assertions referencing `Checkout.totalPrice`

All test files that contain GraphQL query strings querying `totalPrice` on the `Checkout` type, or that assert against `data["checkout"]["totalPrice"]`, must be updated to use `totalGrossAmount`.

> **Important**: References to `CheckoutLine.totalPrice` (e.g., `lines[0]["totalPrice"]`) and `OrderLine.totalPrice` must **NOT** be changed.

#### Checkout GraphQL Test Files (query strings + assertions)

| # | File | Checkout-level `totalPrice` refs |
|---|------|----------------------------------|
| 1 | `saleor/graphql/checkout/tests/benchmark/test_homepage.py` | Query strings (lines 56, 104) |
| 2 | `saleor/graphql/checkout/tests/benchmark/test_checkout_mutations.py` | Query strings (lines 96, 168, 224, 1513, 1578) |
| 3 | `saleor/graphql/checkout/tests/benchmark/test_checkout.py` | Query strings (lines 31) |
| 4 | `saleor/graphql/checkout/tests/test_checkouts_query.py` | Query string (line 29) |
| 5 | `saleor/graphql/checkout/tests/test_checkout_discount_expiration.py` | Query string (line 54) |
| 6 | `saleor/graphql/checkout/tests/mutations/test_checkout_add_promo_code.py` | Query string (line 54), assertions (lines 109, 158, 884, 911, 929, 1301) |
| 7 | `saleor/graphql/checkout/tests/mutations/test_checkout_create.py` | Query string (line 42) |
| 8 | `saleor/graphql/checkout/tests/mutations/test_checkout_remove_promo_code.py` | Query string (line 48), assertions (line 659) |
| 9 | `saleor/graphql/checkout/tests/mutations/test_checkout_lines_add.py` | Query string (line 57) |
| 10 | `saleor/graphql/checkout/tests/mutations/test_checkout_lines_update.py` | Query string (line 61), assertions (lines 502, 819, 879, 934) |
| 11 | `saleor/graphql/checkout/tests/mutations/test_checkout_delivery_method_update.py` | Query string (line 56) |
| 12 | `saleor/graphql/checkout/tests/test_checkout.py` | Query strings (lines 1810, 1922), assertions (lines 2041, 2109, 2232, 2407, 2560, 2709, 2792, 2896, 2955, 3038, 3110, 3197, 3271, 3358, 3435, 3524, 3617, 3694, 3738, 3966) |
| 13 | `saleor/graphql/checkout/tests/test_checkout_promo_codes.py` | Query string (line 21), assertion (line 52) |
| 14 | `saleor/graphql/checkout/tests/deprecated/test_checkout_promo_codes.py` | Query string (line 26) |
| 15 | `saleor/graphql/checkout/tests/test_checkout_line_problems.py` | Query strings (lines 536, 545 – checkout-level) |
| 16 | `saleor/graphql/account/tests/queries/test_me.py` | Query strings (lines 123, 147, 293 – checkout-level) |
| 17 | `saleor/graphql/tests/queries/fragments.py` | Query fragment (line 552 – checkout-level) |
| 18 | `saleor/graphql/tests/test_context.py` | Checkout totalPrice reference |
| 19 | `saleor/graphql/tests/test_tracing.py` | Checkout totalPrice reference |
| 20 | `saleor/graphql/payment/tests/mutations/test_payment_gateway_initialize.py` | Checkout totalPrice reference |
| 21 | `saleor/graphql/webhook/tests/test_subscription_payload.py` | Checkout totalPrice reference |

#### Webhook Test Files

| # | File | `totalPrice` refs |
|---|------|-------------------|
| 1 | `saleor/webhook/tests/subscription_webhooks/subscription_queries.py` | `CHECKOUT_CREATED` query (line 2091) |
| 2 | `saleor/webhook/tests/fixtures/webhook.py` | Fixture query (line 105) |
| 3 | `saleor/webhook/transport/asynchronous/tests/test_deferred_payload.py` | Assertion (line 143) |
| 4 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_subscription.py` | Assertion + query (lines 2375, 3050) |
| 5 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_transaction_refund_requested.py` | Assertion (line 220) |
| 6 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_transaction_cancelation_requested.py` | Assertion (line 182) |
| 7 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_transaction_process_session.py` | Query (line 35), assertions (lines 122, 188) |
| 8 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_transaction_initialize_session.py` | Query (line 37), assertions (lines 127, 197) |
| 9 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_payment_gateway_initialize_session.py` | Query (line 19), assertions (lines 65, 98) |
| 10 | `saleor/webhook/tests/subscription_webhooks/test_create_deliveries_for_transaction_charge_requested.py` | Assertion (line 184) |

#### App Test Fixtures

| # | File | `totalPrice` refs |
|---|------|-------------------|
| 1 | `saleor/app/tests/fixtures/webhooks/payment_app.py` | Query strings (lines 220, 278) |
| 2 | `saleor/app/tests/fixtures/webhooks/tax_app.py` | Query string (line 116) |

#### Checkout Tax Webhook Tests

| # | File | `totalPrice` refs |
|---|------|-------------------|
| 1 | `saleor/checkout/tests/webhooks/subscriptions/test_calculate_taxes.py` | Checkout-level totalPrice reference |

#### E2E Test Utility Files (shared query fragments)

These utility files define GraphQL query strings used across many E2E tests. Changing these will cascade to all E2E tests that import them.

| # | File | `totalPrice` refs |
|---|------|-------------------|
| 1 | `saleor/tests/e2e/checkout/utils/checkout_create.py` | Query strings (lines 33, 85) |
| 2 | `saleor/tests/e2e/checkout/utils/query_checkout.py` | Query string (line 11) |
| 3 | `saleor/tests/e2e/checkout/utils/checkout_lines_add.py` | Query string (line 39) |
| 4 | `saleor/tests/e2e/checkout/utils/checkout_delivery_method_update.py` | Query string (line 20) |
| 5 | `saleor/tests/e2e/checkout/utils/checkout_complete.py` | Query string (line 102) |
| 6 | `saleor/tests/e2e/checkout/utils/checkout_add_promo_code.py` | Query string (line 8) |
| 7 | `saleor/tests/e2e/checkout/utils/checkout_remove_promo_code.py` | Query string (line 17) |
| 8 | `saleor/tests/e2e/checkout/utils/checkout_lines_update.py` | Query string (line 16) |
| 9 | `saleor/tests/e2e/checkout/utils/checkout_lines_delete.py` | Query string (line 16) |
| 10 | `saleor/tests/e2e/checkout/utils/checkout_create_from_order.py` | Query string (line 20) |

#### E2E Test Files (assertions referencing `checkout_data["totalPrice"]`)

There are approximately **65+ E2E test files** under `saleor/tests/e2e/checkout/` and `saleor/tests/e2e/orders/` that reference `totalPrice` on checkout data. Each assertion like `checkout_data["totalPrice"]["gross"]["amount"]` must be updated to `checkout_data["totalGrossAmount"]["gross"]["amount"]`.

Key affected directories:
- `saleor/tests/e2e/checkout/discounts/promotions/` (8 files)
- `saleor/tests/e2e/checkout/discounts/sales/` (5 files)
- `saleor/tests/e2e/checkout/discounts/vouchers/` (17 files)
- `saleor/tests/e2e/checkout/discounts/` (2 files)
- `saleor/tests/e2e/checkout/taxes/` (8 files)
- `saleor/tests/e2e/checkout/shipping/` (2 files)
- `saleor/tests/e2e/checkout/zero_total/` (4 files)
- `saleor/tests/e2e/checkout/` (direct - ~18 files)

---

## Out of Scope (NOT Changed)

The following `totalPrice` references are **NOT** part of this change:

1. **`CheckoutLine.totalPrice`** — This is a separate field on the `CheckoutLine` type (`saleor/graphql/checkout/types.py`, ~line 308). It remains `totalPrice`.
2. **`OrderLine.totalPrice`** — This is on the `OrderLine` type. Not affected.
3. **`Order.totalPrice`** — Order-level references. Not affected.
4. **`baseSubtotalPrice`** — This is a different field used in promotion rule predicates. Not affected.
5. **Underlying model fields** — `Checkout.total`, `Checkout.total_net_amount`, `Checkout.total_gross_amount` in `saleor/checkout/models.py` — these database model fields remain unchanged. The GraphQL field name changes but the resolver still reads from `checkout_info.checkout.total`.
6. **`subtotalPrice`** — Separate field, not affected.

---

## Consumer Repository Impact Reports

### configurator

# Consumer Impact Report

## Source Change: Rename `Checkout.totalPrice` → `Checkout.totalGrossAmount`

**Generated**: 2026-04-27
**Consumer Repository**: `@saleor/configurator`
**Source Repository**: `saleor/saleor` (Saleor Core GraphQL API)

---

## 4.1 Executive Summary

| Field | Value |
|-------|-------|
| **Consumer Repository** | `@saleor/configurator` v1.3.0 |
| **Source Change** | Rename `totalPrice` → `totalGrossAmount` on the `Checkout` GraphQL type |
| **Dependency Type** | Schema-level integration via embedded GraphQL schema + `gql.tada` codegen |
| **Schema Version** | Saleor API v3.20 |
| **Total Usages Found** | 10 references to `totalPrice` across 2 generated files |
| **Affected by Rename** | 2 references (both in auto-generated files on the `Checkout` type) |
| **Not Affected** | 8 references (on `CheckoutLine`, `OrderLine`, `OrderBulkCreateOrderLineInput`, `TaxableObjectLine`) |

### Severity Breakdown

| Severity | Count |
|----------|-------|
| Breaking | 0 |
| Behavioral | 0 |
| Requires Update | 0 |
| **Requires Regeneration** | **2** |
| No Impact | 8 |

### Key Finding

**This repository has ZERO hand-written code that references `Checkout.totalPrice`.** The `@saleor/configurator` CLI is a store configuration tool that manages channels, products, categories, shipping zones, and other administrative settings. It does **not** perform checkout operations or query checkout pricing data.

The only impact is to **two auto-generated files** (`schema.graphql` and `graphql-env.d.ts`) that contain the full Saleor API schema for type-checking purposes via the `gql.tada` TypeScript plugin. These files are automatically regenerated by running `pnpm fetch-schema` and will update without any manual code changes.

**No manual code changes are required.**

---

## 4.2 Dependency Information

| Field | Value |
|-------|-------|
| **Dependency Mechanism** | Embedded GraphQL schema + `gql.tada` TypeScript plugin |
| **Direct NPM Dependency on Saleor** | None — no `@saleor/core` or similar package in `package.json` |
| **Schema Source** | `https://raw.githubusercontent.com/saleor/saleor/3.20/saleor/graphql/schema.graphql` |
| **Schema Version** | `3.20` (from `package.json` → `saleor.schemaVersion`) |
| **Schema Location** | `src/lib/graphql/schema.graphql` (961.80 KB, 47,392 lines) |
| **Generated Types Location** | `src/lib/graphql/graphql-env.d.ts` (1,266.51 KB, 47,385 lines) |
| **Type Generation Tool** | `gql.tada` v1.8.5+ with TS plugin configured in `tsconfig.json` |
| **Schema Fetch Script** | `src/lib/graphql/fetch-schema.ts` (invoked via `pnpm fetch-schema`) |
| **Manifest File** | `package.json` (line: `"saleor": { "schemaVersion": "3.20" }`) |

### How the Schema Integration Works

1. `package.json` declares `saleor.schemaVersion: "3.20"`
2. `pnpm fetch-schema` runs `src/lib/graphql/fetch-schema.ts`, which fetches the schema from GitHub
3. The schema is written to `src/lib/graphql/schema.graphql`
4. `tsconfig.json` configures the `gql.tada/ts-plugin` to read this schema file
5. `gql.tada` generates `src/lib/graphql/graphql-env.d.ts` with TypeScript type definitions
6. Application code uses `gql.tada` for type-safe GraphQL operations

---

## 4.3 Impact Summary Table

### Affected References (Requires Regeneration)

| File | Line | Layer | Usage Type | Severity | Required Change |
|------|------|-------|-----------|----------|----------------|
| `src/lib/graphql/schema.graphql` | 14035 | Shared Types | `generated_code` | Requires Regeneration | Re-fetch schema via `pnpm fetch-schema` after Saleor core updates schema version. Field will change from `totalPrice: TaxedMoney!` to `totalGrossAmount: TaxedMoney!` on `Checkout` type. |
| `src/lib/graphql/graphql-env.d.ts` | 7189–7196 | Shared Types | `generated_code` | Requires Regeneration | Auto-regenerated by `gql.tada` after schema file is updated. The `totalPrice` field entry in the `Checkout` object type definition will be replaced with `totalGrossAmount`. |

### Unaffected References (No Impact)

| File | Line | Layer | Parent Type | Reason |
|------|------|-------|-------------|--------|
| `src/lib/graphql/schema.graphql` | 14521 | Shared Types | `CheckoutLine` | Different type — only `Checkout.totalPrice` is renamed |
| `src/lib/graphql/schema.graphql` | 15608 | Shared Types | `OrderLine` | Different type |
| `src/lib/graphql/schema.graphql` | 33948 | Shared Types | `OrderBulkCreateOrderLineInput` | Different type (input) |
| `src/lib/graphql/schema.graphql` | 46946 | Shared Types | `TaxableObjectLine` | Different type |
| `src/lib/graphql/graphql-env.d.ts` | 8113 | Shared Types | `CheckoutLine` | Different type |
| `src/lib/graphql/graphql-env.d.ts` | 21338 | Shared Types | `OrderBulkCreateOrderLineInput` | Different type |
| `src/lib/graphql/graphql-env.d.ts` | 23440 | Shared Types | `OrderLine` | Different type |
| `src/lib/graphql/graphql-env.d.ts` | 41869 | Shared Types | `TaxableObjectLine` | Different type |

---

## 4.4 Detailed Impact Analysis

### File 1: `src/lib/graphql/schema.graphql`

**File type**: Auto-generated (fetched from Saleor GitHub repository)
**File size**: 961.80 KB (47,392 lines)

#### Affected Reference

- **Line 14035**: `Checkout.totalPrice`
- **Parent type**: `type Checkout implements Node & ObjectWithMetadata` (defined at line 13779)
- **Code snippet**:
  ```graphql
  """
  Triggers the following webhook events:
  - CHECKOUT_CALCULATE_TAXES (sync): Optionally triggered when checkout prices are expired.
  """
  totalPrice: TaxedMoney!
    @webhookEventsInfo(asyncEvents: [], syncEvents: [CHECKOUT_CALCULATE_TAXES])
  ```
- **Usage type**: `generated_code`
- **Severity**: **Requires Regeneration**
- **Reasoning**: This file is a verbatim copy of the Saleor core GraphQL schema. When the source repository renames `Checkout.totalPrice` to `Checkout.totalGrossAmount`, this file must be re-fetched to stay in sync.
- **Required action**: Run `pnpm fetch-schema` after updating `saleor.schemaVersion` in `package.json` to the version containing the rename. The field will automatically change to `totalGrossAmount: TaxedMoney!`.

---

### File 2: `src/lib/graphql/graphql-env.d.ts`

**File type**: Auto-generated by `gql.tada` TypeScript plugin
**File size**: 1,266.51 KB (47,385 lines)

#### Affected Reference

- **Lines 7189–7196**: `Checkout.totalPrice` type entry
- **Parent type**: `Checkout` OBJECT type (defined at line 6868)
- **Code snippet**:
  ```typescript
  totalPrice: {
    name: "totalPrice";
    type: {
      kind: "NON_NULL";
      name: never;
      ofType: { kind: "OBJECT"; name: "TaxedMoney"; ofType: null };
    };
  };
  ```
- **Usage type**: `generated_code`
- **Severity**: **Requires Regeneration**
- **Reasoning**: This file is auto-generated by the `gql.tada` plugin from `schema.graphql`. Once the schema file is updated, this file will be regenerated on the next TypeScript build or IDE reload.
- **Required action**: No manual action needed — this file auto-regenerates when the schema changes. After running `pnpm fetch-schema`, run `pnpm typecheck` or open the project in an IDE to trigger regeneration.

---

### File 3: `src/lib/graphql/graphql-types.ts`

**File type**: Manually defined subset of GraphQL input types
**File size**: 1.04 KB (39 lines)

- **totalPrice references**: **None** (0 occurrences)
- **Severity**: **No Impact**
- **Reasoning**: This file only contains manually-defined input types for `CollectionChannelListingUpdateInput`, `PublishableChannelListingInput`, `AttributeValueSelectableTypeInput`, and `AttributeValueInput`. None reference checkout or pricing fields.

---

## 4.5 Effort Estimate

| Metric | Count |
|--------|-------|
| Files requiring **manual changes** | **0** |
| Files requiring **regeneration** | **2** (`schema.graphql`, `graphql-env.d.ts`) |
| Files requiring **schema sync** | **1** (`schema.graphql` — source file for regeneration) |
| Breaking changes in hand-written code | **0** |
| Documentation files needing updates | **0** |
| Test files needing updates | **0** |
| **Estimated effort** | **Low** (0 manual code changes, 1 automated command) |

### Effort Breakdown

| Task | Time | Type |
|------|------|------|
| Update `saleor.schemaVersion` in `package.json` | ~1 min | Manual (1 line change in config) |
| Run `pnpm fetch-schema` | ~10 sec | Automated |
| Verify regenerated types with `pnpm typecheck` | ~30 sec | Automated |
| Total | **< 2 minutes** | |

---

## 4.6 Migration Recommendations

### Order of Operations

1. **Wait** for the Saleor core repository to deploy the schema change and tag the new version
2. **Update** `saleor.schemaVersion` in `package.json` from `"3.20"` to the new version containing the rename
3. **Run** `pnpm fetch-schema` to download the updated schema
4. **Verify** with `pnpm typecheck` — should pass with zero errors since no hand-written code references `Checkout.totalPrice`
5. **Commit** the updated `schema.graphql`, `graphql-env.d.ts`, and `package.json`
6. **Release** via normal changeset workflow

### Timing

- **Can changes be made before source deploys?** No — the schema must be fetched from the Saleor repository after the rename is merged and tagged.
- **Can changes be made after source deploys?** Yes — and this is the recommended approach. The configurator does not query `Checkout.totalPrice`, so there is no urgency.
- **Deployment coordination required?** None — the configurator is a CLI tool that manages store configuration, not a real-time service consuming checkout data.

### Automation Possibilities

- The entire migration can be automated in CI/CD:
  1. Update version in `package.json`
  2. `pnpm fetch-schema`
  3. `pnpm typecheck`
  4. Commit and create PR
- A Dependabot-style automation could monitor the Saleor schema version and auto-create PRs when new versions are tagged.

### Test Files Needing Updates

None — no test files reference `totalPrice` or `Checkout.totalPrice`.

---

## 4.7 Unimpacted Areas

### Other Types with `totalPrice` (Not Affected by Rename)

The following types also have a `totalPrice` field, but the source change **only** renames the field on the `Checkout` type. These are unaffected:

| Type | File | Line | Field Signature | Why Unaffected |
|------|------|------|----------------|---------------|
| `CheckoutLine` | `schema.graphql` | 14521 | `totalPrice: TaxedMoney!` | Different type — `CheckoutLine.totalPrice` is NOT being renamed |
| `OrderLine` | `schema.graphql` | 15608 | `totalPrice: TaxedMoney!` | Different type — order line pricing |
| `OrderBulkCreateOrderLineInput` | `schema.graphql` | 33948 | `totalPrice: TaxedMoneyInput!` | Different type — bulk order input |
| `TaxableObjectLine` | `schema.graphql` | 46946 | `totalPrice: Money!` | Different type — tax calculation line |

### Pre-Filter Results (217 files) — False Positives

The pre-filter grep matched 217 files in this repository. These matches are **false positives** — they matched the word "checkout" in unrelated contexts, NOT `totalPrice`. Examples:

| Pattern Matched | Context | Files |
|----------------|---------|-------|
| `limitQuantityPerCheckout` | Shop settings for max checkout quantity | Config schema, service, repository files |
| `automaticallyCompleteFullyPaidCheckouts` | Channel checkout behavior setting | Channel service, config service |
| `checkoutSettings` | Channel checkout configuration object | Multiple module files |
| `CHECKOUT_URL` | Environment variable for storefront URL | Plugin documentation |
| `checkoutComplete` | Documentation reference to mutation | Schema comments |

None of these reference `Checkout.totalPrice` or checkout pricing calculations.

### Application Business Logic — Unaffected

The configurator CLI tool operates on these Saleor entities:
- ✅ Channels (create, update, configure)
- ✅ Products (create, update, configure)
- ✅ Categories (create, configure hierarchy)
- ✅ Collections (create, assign products)
- ✅ Attributes (create, assign values)
- ✅ Shipping Zones (create, configure rates)
- ✅ Shop Settings (update global settings)
- ✅ Tax Configuration
- ✅ Warehouse Configuration

It does **NOT** operate on:
- ❌ Checkout creation or management
- ❌ Checkout pricing queries
- ❌ Order creation or management
- ❌ Payment processing

---

## 4.8 Cross-Cutting Concerns

### Re-exports to Downstream Consumers

The `@saleor/configurator` package is published to NPM (`publishConfig.access: "public"`). However:

- The published package (`dist/` directory) contains only the compiled CLI tool
- It does **NOT** export or re-export the GraphQL schema, type definitions, or any Checkout-related types
- The `files` array in `package.json` includes: `dist`, `bin`, `recipes`, `README.md`, `LICENSE`, `schema.json` (JSON Schema for config YAML), `SCHEMA.md`
- None of these published artifacts contain `totalPrice` or checkout pricing references

**Conclusion**: Downstream consumers of `@saleor/configurator` are **NOT affected** by this change.

### Coordinated Deployment Requirements

**None.** The configurator is a CLI tool used during store setup/configuration. It is not a real-time service that processes checkout data. The schema can be updated at any convenient time after the source change is deployed.

### Shared Infrastructure Concerns

- **Database**: None — the configurator reads/writes via the Saleor GraphQL API, not directly to any database
- **Message Queues**: None — the configurator does not consume or produce events
- **Configuration**: None — the `totalPrice` field is not referenced in any configuration files (YAML, JSON, env vars)

---

## Appendix: Search Methodology

The following searches were performed to arrive at these findings:

1. **Source code search**: `grep -rn "totalPrice"` across all `.ts`, `.tsx`, `.js`, `.jsx` files in `src/` (excluding generated files) → **0 results**
2. **Test file search**: `grep -rn "totalPrice"` across all test files in `tests/` → **0 results**
3. **Config file search**: `grep -rn "totalPrice"` across `.yml`, `.yaml`, `.json` files → **0 results**
4. **Documentation search**: `grep -rn "totalPrice"` across `docs/`, `plugin/`, `specs/`, `.claude/`, `.serena/`, `SCHEMA.md`, `README.md`, `CHANGELOG.md` → **0 results**
5. **Schema file search**: `grep -n "totalPrice"` in `schema.graphql` → **6 results** (1 on Checkout type, 5 on other types)
6. **Generated types search**: `grep -n "totalPrice"` in `graphql-env.d.ts` → **11 lines** (2 for Checkout type, 9 for other types + `subtotalPrice`/`baseSubtotalPrice` partial matches)
7. **Manual types search**: `grep -n "totalPrice"` in `graphql-types.ts` → **0 results**
8. **Reverse search for new name**: `grep -rn "totalGrossAmount"` across entire repo → **0 results**

---

### awesome-saleor

# Impact Report: `awesome-saleor`

## 1. Executive Summary

| Field | Value |
|-------|-------|
| **Consumer Repository** | `awesome-saleor` |
| **Source Change Request** | Rename `totalPrice` field to `totalGrossAmount` on the `Checkout` GraphQL type in the Saleor core API |
| **Dependency Type** | **None** — no dependency of any kind exists |
| **Total Usages Found** | 0 |
| **Severity Breakdown** | Breaking: 0 · Behavioral: 0 · Requires Update: 0 · Requires Regeneration: 0 · No Impact: 0 |

### Key Finding

**This repository is completely unimpacted by the source change.**

`awesome-saleor` is a documentation-only repository containing a curated "awesome list" of links to Saleor-related tools, libraries, apps, and resources. It consists of exactly two files — `README.md` and `CONTRIBUTING.md` — neither of which contains source code, dependency manifests, GraphQL schemas, API client code, or any programmatic reference to the Saleor core API. There is no code-level dependency on Saleor, and no changes are required in this repository as a result of the `totalPrice` → `totalGrossAmount` rename.

---

## 2. Dependency Information

| Check | Result |
|-------|--------|
| Package dependency (`package.json`, `requirements.txt`, `pyproject.toml`, etc.) | ❌ Not found — no dependency manifests exist |
| Git submodule (`.gitmodules`) | ❌ Not found |
| Vendored/copied code | ❌ Not found — no source code files exist |
| API-level integration (HTTP clients, GraphQL queries) | ❌ Not found |
| GraphQL schema files | ❌ Not found |
| Shared database or message queue contracts | ❌ Not found |
| Shared configuration or environment variables | ❌ Not found |

**Conclusion**: No dependency of any kind exists between `awesome-saleor` and the Saleor core API.

---

## 3. Impact Summary Table

| File | Line | Layer | Usage Type | Severity | Required Change |
|------|------|-------|-----------|----------|----------------|
| *(none)* | — | — | — | — | — |

No impacted usages were found.

---

## 4. Detailed Impact Analysis

No impacted files exist. The repository contains only:

| File | Description | Contains Changed Symbols? |
|------|-------------|--------------------------|
| `README.md` | Curated list of Saleor tools, apps, and resources (Markdown links only) | **No** |
| `CONTRIBUTING.md` | Contribution guidelines for the awesome list | **No** |

### Symbol Search Results

| Symbol Searched | Matches Found |
|----------------|---------------|
| `totalPrice` | 0 |
| `total_price` | 0 |
| `totalGrossAmount` | 0 |
| `total_gross_amount` | 0 |
| `TaxedMoney` | 0 |
| `Checkout` (in GraphQL context) | 0 |

The word "checkout" appears at `README.md` lines 69–70 as part of a Markdown link to the external [Abandoned Checkouts](https://github.com/saleor/saleor-app-abandoned-checkouts) app. This is a URL reference to a separate GitHub repository and is **not** a code dependency, API call, or schema reference. It has zero relevance to the `totalPrice` field rename.

---

## 5. Effort Estimate

| Metric | Count |
|--------|-------|
| Files requiring manual changes | 0 |
| Files requiring regeneration | 0 |
| Files requiring schema sync | 0 |
| Breaking changes in hand-written code | 0 |
| **Estimated effort** | **None** — no changes required |

---

## 6. Migration Recommendations

No migration is needed. This repository requires **zero changes** in response to the `totalPrice` → `totalGrossAmount` rename in the Saleor core API.

- **Order of operations**: N/A
- **Pre/post deploy coordination**: N/A
- **Automation possibilities**: N/A
- **Test files needing updates**: N/A
- **Deployment coordination**: N/A

---

## 7. Unimpacted Areas

| File | Reference | Why Unimpacted |
|------|-----------|---------------|
| `README.md:69-70` | "Abandoned Checkouts" link (`https://github.com/saleor/saleor-app-abandoned-checkouts`) | This is a Markdown hyperlink to an external GitHub repository. It is not a code reference, import, API call, or schema usage. The word "Checkouts" in the app name is unrelated to the `Checkout.totalPrice` field. |

---

## 8. Cross-Cutting Concerns

- **Re-exports**: None — this repository contains no code and does not re-export any symbols.
- **Coordinated deployment**: None required.
- **Downstream consumers**: None — this repository is a static documentation list with no downstream code consumers.
- **Shared infrastructure**: None — no databases, queues, or configuration are involved.

### Note on Linked Projects

While `awesome-saleor` links to many Saleor apps and tools that *may* be impacted by the `totalPrice` → `totalGrossAmount` rename (e.g., storefront templates, app templates, payment apps), those are **separate repositories** and would need their own independent impact scans. The links in this README do not constitute a code dependency.

---

*Report generated as part of the Consumer Impact Scan analysis.*

---

### saleor-graphql-playground

# Impact Report: `totalPrice` → `totalGrossAmount` Rename on Checkout Type

## 4.1 Executive Summary

| Field | Value |
|-------|-------|
| **Consumer Repository** | `saleor-graphql-playground` (`@saleor/graphql-playground` v3.0.0) |
| **Source Change Request** | Rename `totalPrice` field to `totalGrossAmount` on the `Checkout` GraphQL type in Saleor Core API |
| **Dependency Type** | API-level integration (runtime introspection) — no package dependency |
| **Total Usages Found** | **0** |
| **Severity Breakdown** | Breaking: 0 · Behavioral: 0 · Requires Update: 0 · Requires Regeneration: 0 · No Impact: 0 |

### Key Finding

**This repository is unimpacted by the `totalPrice` → `totalGrossAmount` rename.** The `saleor-graphql-playground` is a generic GraphiQL-based playground UI that dynamically fetches the Saleor GraphQL schema via introspection at runtime. It contains **zero** hardcoded references to `totalPrice`, `total_price`, `totalGrossAmount`, `total_gross_amount`, or the `Checkout` GraphQL type anywhere in its codebase. The playground will automatically reflect the renamed field after the source change is deployed — no code changes are required in this repository.

---

## 4.2 Dependency Information

| Field | Value |
|-------|-------|
| **Package Name** | N/A — no npm/pip package dependency on Saleor Core |
| **Version Constraint** | N/A |
| **Direct or Transitive** | N/A (API-level integration only) |
| **Manifest File** | N/A |
| **Schema Version** | N/A — schema fetched dynamically via introspection |

### Dependency Details

This consumer repository has an **API-level runtime dependency** on the Saleor GraphQL API, not a package-level dependency. The relationship works as follows:

1. **Runtime Introspection**: `src/useFetcher.tsx` uses `getIntrospectionQuery()` from the `graphql` package to fetch the full schema from a configurable Saleor GraphQL endpoint (default: `https://master.staging.saleor.cloud/graphql/`).
2. **Dynamic Schema Building**: The introspection result is passed to `buildClientSchema()` to construct the schema object used by GraphiQL for autocomplete, validation, and the schema explorer.
3. **No Cached Schema**: There are no `.graphql`, `.gql`, or schema definition files committed to this repository. The schema is always fetched live.
4. **Configurable Endpoint**: The Saleor GraphQL endpoint URL is passed via `data-endpoint` attribute in HTML templates, making this playground generic and not hardcoded to any specific Saleor instance.

**Checked and ruled out:**
- ❌ No npm package dependency on `saleor` or `@saleor/core`
- ❌ No `.gitmodules` file (no git submodule references)
- ❌ No vendored or copied code from the Saleor core repository
- ❌ No GraphQL schema files synced from Saleor core
- ❌ No codegen configuration (no `.graphqlrc`, `codegen.ts`, `graphql.config.*`)
- ❌ No shared database or message queue contracts

---

## 4.3 Impact Summary Table

| File | Line | Layer | Usage Type | Severity | Required Change |
|------|------|-------|-----------|----------|----------------|
| *(No impacted usages found)* | — | — | — | — | — |

**No usages of the changed symbols (`totalPrice`, `total_price`, `Checkout`) were found anywhere in this repository.**

---

## 4.4 Detailed Impact Analysis

### Search Results Summary

A comprehensive search was performed across all files in the repository using the following search patterns:

| Search Pattern | Files Searched | Matches Found |
|---------------|---------------|---------------|
| `totalPrice` | All `.tsx`, `.ts`, `.js`, `.mjs`, `.html`, `.json`, `.yaml`, `.yml`, `.md`, `.graphql`, `.gql`, `.css` | **0** |
| `total_price` | Same file types | **0** |
| `totalGrossAmount` | Same file types | **0** |
| `total_gross_amount` | Same file types | **0** |
| `Checkout` | Same file types | **0** |

### Files Manually Reviewed

Every source file in the repository was read and analyzed for potential indirect references:

| File | Contents Summary | References to Changed Symbols |
|------|-----------------|------------------------------|
| `src/useFetcher.tsx` | Creates GraphiQL fetcher, runs introspection query, builds client schema | None — uses generic `getIntrospectionQuery()` |
| `src/useGraphQLEditorContent.tsx` | URL sharing: serializes/deserializes user queries to URL hash fragments | None — encodes arbitrary user-typed queries, not specific fields |
| `src/Root.tsx` | Main React component, renders GraphiQL with explorer plugin | None |
| `src/index.tsx` | Entry point, `createPlayground()` export | None |
| `src/CopyPlaygroundDialog.tsx` | Share dialog UI for copying URL and curl | None |
| `src/curl.ts` | Converts editor content to curl command | None |
| `src/types.ts` | `EditorContent` type definition (query, variables, headers, operationName) | None |
| `src/utils.ts` | `removeEmptyValues` utility function | None |
| `src/style.css` | Custom CSS overrides for GraphiQL | None |
| `src/ArrowUpOnSquareIcon.tsx` | SVG icon component | None |
| `src/useEvent.ts` | React `useEvent` hook utility | None |
| `graphql/cdn.html` | CDN-hosted playground demo page | Default query is `products` — no `Checkout` references |
| `graphql/index.html` | Local dev playground demo page | Default query is `products` — no `Checkout` references |
| `index.html` | Root playground demo page | Default query is `products` — no `Checkout` references |
| `package.json` | Package manifest | No Saleor core dependency |
| `README.md` | Documentation | No `totalPrice` or `Checkout` references |
| `.github/workflows/check-licenses.yaml` | CI workflow for license checking | No relevant references |

### Indirect / Dynamic Reference Analysis

| Reference Path | Analysis | Impact |
|---------------|----------|--------|
| **Runtime Introspection** (`src/useFetcher.tsx`) | Schema fetched dynamically via `getIntrospectionQuery()` — never hardcoded | **None** — playground auto-discovers the schema |
| **Default Queries** (HTML `data-query` attributes) | All three HTML files use a `products` query — no `Checkout` type referenced | **None** |
| **URL Sharing** (`src/useGraphQLEditorContent.tsx`) | Encodes arbitrary user-typed queries into LZ-compressed URL fragments | **None in codebase** — previously shared URLs with `totalPrice` queries would fail at the API level, not in this repo |
| **Curl Export** (`src/curl.ts`) | Converts user-typed queries to curl commands | **None** — passes through user content |
| **Test Files / Fixtures** | No test files, mock data, or fixtures exist in this repository | **None** |

---

## 4.5 Effort Estimate

| Metric | Count |
|--------|-------|
| Files requiring manual changes | **0** |
| Files requiring regeneration | **0** |
| Files requiring schema sync | **0** |
| Breaking changes in hand-written code | **0** |
| **Estimated effort** | **None (0 changes)** |

No code changes are required in this repository.

---

## 4.6 Migration Recommendations

### Action Required: None

This repository requires **zero code changes** to accommodate the `totalPrice` → `totalGrossAmount` rename on the `Checkout` type.

### Order of Operations

1. The Saleor core change can be deployed independently — no coordination with this repository is needed.
2. After the Saleor core change is deployed, the playground will automatically reflect the new `totalGrossAmount` field in the schema explorer and autocomplete.

### Pre-deploy vs. Post-deploy

- **No pre-deploy changes needed** in this repository.
- **No post-deploy changes needed** in this repository.

### Automation Possibilities

- N/A — no changes to automate.

### Test Files That Need Updates

- N/A — this repository has no test files.

### Deployment Coordination Requirements

- **None.** The playground is decoupled from the Saleor core schema at the code level. It fetches the schema dynamically at runtime.

### User-Facing Considerations

- **Shared Playground URLs**: Users who previously shared playground URLs (via the "Share Playground" feature) that contain queries selecting `totalPrice` on the `Checkout` type will experience a **GraphQL validation error** when those queries are executed against the updated Saleor API. This is an API-level breaking change, not a codebase issue.
- **Browser History / Saved Tabs**: GraphiQL persists query tabs in browser `localStorage`. Users who have saved `Checkout { totalPrice { ... } }` queries in their browser will need to manually update those queries to use `totalGrossAmount`.

---

## 4.7 Unimpacted Areas

All files in this repository are confirmed **unaffected** by the source change. Below is the reasoning for each area:

| Area | Files | Reason Unaffected |
|------|-------|-------------------|
| **Schema Fetching** | `src/useFetcher.tsx` | Uses generic `getIntrospectionQuery()` — does not reference any specific type or field names |
| **UI Components** | `src/Root.tsx`, `src/CopyPlaygroundDialog.tsx`, `src/ArrowUpOnSquareIcon.tsx` | Generic UI components that render GraphiQL — no domain-specific type references |
| **Query Sharing** | `src/useGraphQLEditorContent.tsx`, `src/curl.ts` | Serializes/deserializes arbitrary user content — no hardcoded queries |
| **Type Definitions** | `src/types.ts` | Defines `EditorContent` type (query, variables, headers, operationName) — generic editor types, not Saleor domain types |
| **Utilities** | `src/utils.ts`, `src/useEvent.ts` | Generic utility functions with no domain references |
| **Entry Point** | `src/index.tsx` | Bootstraps React app — no domain references |
| **Styles** | `src/style.css` | CSS overrides for GraphiQL UI — no domain references |
| **HTML Templates** | `index.html`, `graphql/index.html`, `graphql/cdn.html` | Default query is `products` — no `Checkout` type referenced |
| **Configuration** | `package.json`, `tsconfig.json`, `rollup.config.mjs`, `tailwind.config.js` | Build/dev configuration — no Saleor core dependency |
| **CI/CD** | `.github/workflows/check-licenses.yaml` | License checking workflow — no schema or API references |
| **Documentation** | `README.md`, `LICENSE` | Development and usage docs — no `totalPrice` or `Checkout` references |

---

## 4.8 Cross-Cutting Concerns

### Runtime Introspection Behavior

The most important cross-cutting observation is that the `saleor-graphql-playground` uses **runtime introspection** to discover the Saleor GraphQL schema. This design choice means:

1. **Automatic Schema Updates**: After the Saleor core change is deployed, any user loading the playground will automatically see `totalGrossAmount` instead of `totalPrice` in the schema explorer, autocomplete suggestions, and documentation panel. No action required.

2. **No Schema Drift Risk**: Since no schema is cached or committed in this repository, there is zero risk of schema drift between this consumer and the source.

### Re-exports / Downstream Propagation

- The `@saleor/graphql-playground` npm package is published publicly and used via CDN in the [Saleor core playground template](https://github.com/saleor/saleor/blob/main/templates/graphql/playground.html).
- Since this package contains no references to `totalPrice` or `Checkout`, it does **not propagate** the breaking change to any further downstream consumers.
- No additional consumer scanning is needed for this package's dependents.

### Shared Infrastructure Concerns

- **GraphQL Endpoint**: The playground connects to configurable Saleor GraphQL endpoints. The endpoint URL and authentication remain unchanged by the `totalPrice → totalGrossAmount` rename.
- **No Shared Database**: This is a frontend-only application with no database.
- **No Message Queues**: This application does not consume or produce any events.
- **No Shared Configuration**: The only configuration is the GraphQL endpoint URL, which is unaffected.

---

## Summary

| Verdict | **UNIMPACTED** |
|---------|---------------|
| Code changes required | 0 |
| Deployment coordination | None |
| Action items | None |

The `saleor-graphql-playground` repository is a generic GraphiQL-based playground UI that is fully decoupled from specific Saleor schema field names. It dynamically discovers the schema via introspection at runtime and contains zero hardcoded references to the `Checkout` type or its `totalPrice` field. No changes are needed in this repository to support the `totalPrice` → `totalGrossAmount` rename.

---

### storefront

# Consumer Impact Report

## Source Change: Rename `totalPrice` → `totalGrossAmount` on `Checkout` GraphQL Type

---

## 1. Executive Summary

| Attribute | Value |
|-----------|-------|
| **Consumer Repository** | `saleor-storefront` (v0.1.0) |
| **Source Change** | Rename `totalPrice` field to `totalGrossAmount` on the `Checkout` GraphQL type in Saleor Core API |
| **Change Type** | Breaking — GraphQL schema field rename |
| **Dependency Type** | GraphQL schema integration via codegen + `@saleor/auth-sdk` (v1.0.3) |
| **Total Usages Found** | 32 references to `totalPrice` across the codebase |
| **Impacted (Checkout-level)** | 13 breaking usages in 9 hand-written files |
| **Requires Regeneration** | 2 codegen output directories |
| **Requires Update** | 10 usages in 5 reference/documentation files |
| **No Impact** | 9 usages (CheckoutLine/OrderLine `totalPrice` — different types, not renamed) |

**Key Finding:** The storefront is a direct consumer of the Saleor Core GraphQL schema through two separate codegen pipelines. The `Checkout.totalPrice` field is used throughout the checkout flow and cart UI components. Once the Saleor API deploys the rename, GraphQL queries requesting `totalPrice` on the `Checkout` type will fail with a field-not-found error, breaking the checkout and cart pages. The fix is straightforward: rename the field in 4 `.graphql` files, regenerate types, and update 5 TypeScript/TSX files. The change is isolated and low-effort (~15 find-and-replace operations).

---

## 2. Dependency Information

| Attribute | Details |
|-----------|---------|
| **Package Name** | `@saleor/auth-sdk` |
| **Version Constraint** | `1.0.3` (exact) |
| **Dependency Type** | Direct npm dependency + GraphQL schema integration |
| **Manifest File** | `package.json` (line 32) |
| **Schema Connection** | `NEXT_PUBLIC_SALEOR_API_URL` environment variable |
| **Codegen Config (Storefront)** | `.graphqlrc.ts` → generates `src/gql/` from `src/graphql/**/*.graphql` |
| **Codegen Config (Checkout)** | `src/checkout/graphql/codegen.ts` → generates `src/checkout/graphql/generated/index.ts` from `src/checkout/graphql/**/*.graphql` |
| **Codegen Command** | `pnpm run generate:all` (runs both `generate` and `generate:checkout`) |
| **Type Re-exports** | `src/checkout/graphql/index.ts` re-exports `CheckoutFragmentFragment` as `CheckoutFragment` |

The storefront does **not** vendor or copy source code from Saleor Core. Instead, it connects to the remote Saleor GraphQL API at runtime and generates TypeScript types from the schema at build time. This means the breaking change will manifest as:
1. **Build-time failure**: Codegen will fail if `.graphql` files request a field that doesn't exist in the updated schema
2. **Runtime failure**: If the API is updated before the storefront code, GraphQL queries will return errors for the `totalPrice` field on `Checkout`

---

## 3. Impact Summary Table

### 3.1 Breaking Changes

| File | Line(s) | Layer | Usage Type | Required Change |
|------|---------|-------|-----------|----------------|
| `src/checkout/graphql/checkout.graphql` | 83 | Shared Types | `graphql_fragment` | Rename `totalPrice` to `totalGrossAmount` in `CheckoutFragment` |
| `src/graphql/CheckoutCreate.graphql` | 40 | Shared Types | `graphql_query` | Rename `totalPrice` to `totalGrossAmount` in mutation response |
| `src/graphql/CheckoutFind.graphql` | 65 | Shared Types | `graphql_query` | Rename `totalPrice` to `totalGrossAmount` in query response |
| `src/graphql/CheckoutLinesUpdate.graphql` | 15 | Shared Types | `graphql_query` | Rename `totalPrice` to `totalGrossAmount` in mutation response |
| `src/checkout/views/saleor-checkout/order-summary.tsx` | 70, 73, 75 | Screen/UI | `function_call` | Change `checkout.totalPrice` to `checkout.totalGrossAmount` (3 occurrences) |
| `src/checkout/views/saleor-checkout/payment-step.tsx` | 147 | Screen/UI | `function_call` | Change `checkout.totalPrice` to `checkout.totalGrossAmount` |
| `src/ui/components/cart/cart-drawer-wrapper.tsx` | 16 | Screen/UI | `function_call` | Change `checkout?.totalPrice` to `checkout?.totalGrossAmount` |
| `src/ui/components/cart/cart-drawer.tsx` | 105, 114, 119, 120 | Screen/UI | `type_reference` + `function_call` | Rename `totalPrice` prop in `CartDrawerProps` interface OR update data access in wrapper |
| `src/app/[channel]/(main)/cart/page.tsx` | 107 | Screen/UI | `function_call` | Change `checkout.totalPrice` to `checkout.totalGrossAmount` |

### 3.2 Requires Regeneration

| Directory | Layer | Usage Type | Required Change |
|-----------|-------|-----------|----------------|
| `src/gql/` (auto-generated) | Shared Types | `generated_code` | Run `pnpm run generate` after updating `.graphql` files and pointing to updated Saleor API |
| `src/checkout/graphql/generated/` (auto-generated) | Shared Types | `generated_code` | Run `pnpm run generate:checkout` after updating `.graphql` files and pointing to updated Saleor API |

### 3.3 Requires Update (Non-Breaking)

| File | Line(s) | Layer | Usage Type | Required Change |
|------|---------|-------|-----------|----------------|
| `src/_reference/.../stripeComponent.tsx` | 67, 68 | Documentation | `string_ref` | Update `checkout.totalPrice` to `checkout.totalGrossAmount` in reference code |
| `src/_reference/.../stripeForm.tsx` | 60 | Documentation | `string_ref` | Update `checkout.totalPrice` to `checkout.totalGrossAmount` in reference code |
| `src/_reference/.../useAdyenDropin.ts` | 52, 266, 284 | Documentation | `string_ref` | Update destructured `totalPrice` and its usages in reference code |
| `skills/.../checkout-management.md` | 120, 157 | Documentation | `string_ref` | Update code examples showing `checkout.totalPrice.gross.amount` and GraphQL query |
| `skills/.../AGENTS.md` | 1665, 1702 | Documentation | `string_ref` | Update code examples showing `checkout.totalPrice.gross.amount` and GraphQL query |

### 3.4 No Impact

| File | Line(s) | Layer | Reason |
|------|---------|-------|--------|
| `src/checkout/graphql/checkout.graphql` | 109 | Shared Types | `totalPrice` on `CheckoutLineFragment` (CheckoutLine type — **not renamed**) |
| `src/graphql/CheckoutCreate.graphql` | 9 | Shared Types | `totalPrice` on checkout lines (CheckoutLine type — **not renamed**) |
| `src/graphql/CheckoutFind.graphql` | 8 | Shared Types | `totalPrice` on checkout lines (CheckoutLine type — **not renamed**) |
| `src/graphql/CheckoutLinesUpdate.graphql` | 8 | Shared Types | `totalPrice` on checkout lines (CheckoutLine type — **not renamed**) |
| `src/checkout/graphql/order.graphql` | 22 | Shared Types | `totalPrice` on `OrderLineFragment` (OrderLine type — **not renamed**) |
| `src/checkout/views/saleor-checkout/order-summary.tsx` | 64, 94 | Screen/UI | `line.totalPrice` accesses CheckoutLine/OrderLine level — **not renamed** |
| `src/ui/components/cart/cart-drawer.tsx` | 19, 297 | Screen/UI | `CartLine` interface + `line.totalPrice` accesses CheckoutLine level — **not renamed** |
| `src/app/[channel]/(main)/cart/page.tsx` | 87 | Screen/UI | `item.totalPrice` accesses CheckoutLine level — **not renamed** |

---

## 4. Detailed Impact Analysis

### 4.1 `src/checkout/graphql/checkout.graphql` — CheckoutFragment

**Severity:** Breaking  
**Layer:** Shared Types (GraphQL Fragment)  
**Context:** `CheckoutFragment` fragment on the `Checkout` type, used by all checkout mutations and queries in the checkout module.

**Impacted Code (line 83):**
```graphql
fragment CheckoutFragment on Checkout {
    # ... other fields ...
    totalPrice {          # ← LINE 83: RENAME to totalGrossAmount
        gross {
            ...Money
        }
        tax {
            ...Money
        }
    }
    # ...
}
```

**Required Change:** Rename `totalPrice` to `totalGrossAmount` at line 83. Do NOT change line 109 (`totalPrice` in `CheckoutLineFragment`) — that's a different type.

**Impact Propagation:** This fragment is used by `checkout` query, `checkoutLinesUpdate`, `checkoutLineDelete`, `checkoutEmailUpdate`, `checkoutCustomerAttach`, `checkoutShippingAddressUpdate`, `checkoutBillingAddressUpdate`, `checkoutDeliveryMethodUpdate`, `checkoutAddPromoCode`, `checkoutRemovePromoCode` — all in the same file. Updating the fragment fixes all of these at once.

---

### 4.2 `src/graphql/CheckoutCreate.graphql` — CheckoutCreate Mutation

**Severity:** Breaking  
**Layer:** Shared Types (GraphQL Mutation)  
**Context:** `CheckoutCreate` mutation, used by `src/lib/checkout.ts` to create new checkouts.

**Impacted Code (line 40):**
```graphql
mutation CheckoutCreate($channel: String!) {
    checkoutCreate(input: { channel: $channel, lines: [] }) {
        checkout {
            # ... lines with totalPrice at line 9 (CheckoutLine - NOT impacted) ...
            totalPrice {          # ← LINE 40: RENAME to totalGrossAmount
                gross {
                    amount
                    currency
                }
            }
        }
    }
}
```

**Required Change:** Rename `totalPrice` to `totalGrossAmount` at line 40. Do NOT change line 9 (CheckoutLine level).

---

### 4.3 `src/graphql/CheckoutFind.graphql` — CheckoutFind Query

**Severity:** Breaking  
**Layer:** Shared Types (GraphQL Query)  
**Context:** `CheckoutFind` query, used by `src/lib/checkout.ts` to look up existing checkouts.

**Impacted Code (line 65):**
```graphql
query CheckoutFind($id: ID!) {
    checkout(id: $id) {
        # ... lines with totalPrice at line 8 (CheckoutLine - NOT impacted) ...
        totalPrice {          # ← LINE 65: RENAME to totalGrossAmount
            gross {
                amount
                currency
            }
        }
    }
}
```

**Required Change:** Rename `totalPrice` to `totalGrossAmount` at line 65. Do NOT change line 8 (CheckoutLine level).

---

### 4.4 `src/graphql/CheckoutLinesUpdate.graphql` — CheckoutLinesUpdate Mutation

**Severity:** Breaking  
**Layer:** Shared Types (GraphQL Mutation)  
**Context:** `CheckoutLinesUpdate` mutation, used by cart actions to update line quantities.

**Impacted Code (line 15):**
```graphql
mutation CheckoutLinesUpdate($checkoutId: ID!, $lines: [CheckoutLineUpdateInput!]!) {
    checkoutLinesUpdate(id: $checkoutId, lines: $lines) {
        checkout {
            # ... lines with totalPrice at line 8 (CheckoutLine - NOT impacted) ...
            totalPrice {          # ← LINE 15: RENAME to totalGrossAmount
                gross {
                    amount
                    currency
                }
            }
        }
    }
}
```

**Required Change:** Rename `totalPrice` to `totalGrossAmount` at line 15. Do NOT change line 8 (CheckoutLine level).

---

### 4.5 `src/checkout/views/saleor-checkout/order-summary.tsx` — Order Summary Component

**Severity:** Breaking  
**Layer:** Screen/UI  
**Context:** `extractCheckoutData()` function extracts order summary data from a `CheckoutFragment` object.

**Impacted Code (lines 70, 73, 75):**
```tsx
function extractCheckoutData(checkout: CheckoutFragment): OrderSummaryData {
    // ...
    return {
        // ...
        currency: checkout.totalPrice?.gross?.currency || localeConfig.fallbackCurrency,  // LINE 70
        subtotal: checkout.subtotalPrice?.gross?.amount || 0,
        shipping: checkout.shippingPrice?.gross?.amount || 0,
        tax: checkout.totalPrice?.tax?.amount || 0,         // LINE 73
        discount: checkout.discount?.amount || 0,
        total: checkout.totalPrice?.gross?.amount || 0,      // LINE 75
    };
}
```

**Required Change:** Replace `checkout.totalPrice` with `checkout.totalGrossAmount` on lines 70, 73, and 75.

**Unimpacted in same file:** Lines 64 and 94 (`line.totalPrice?.gross?.amount`) access CheckoutLine/OrderLine `totalPrice` — NOT affected.

---

### 4.6 `src/checkout/views/saleor-checkout/payment-step.tsx` — Payment Step Component

**Severity:** Breaking  
**Layer:** Screen/UI  
**Context:** `PaymentStep` component extracts the total price to display on the pay button.

**Impacted Code (line 147):**
```tsx
const total = checkout.totalPrice?.gross;  // LINE 147
const totalStr = formatMoneyWithFallback(total);
```

**Required Change:** Replace `checkout.totalPrice` with `checkout.totalGrossAmount` on line 147.

---

### 4.7 `src/ui/components/cart/cart-drawer-wrapper.tsx` — Cart Drawer Wrapper (Server Component)

**Severity:** Breaking  
**Layer:** Screen/UI  
**Context:** Server component that fetches checkout data and passes it to the client-side `CartDrawer`.

**Impacted Code (line 16):**
```tsx
<CartDrawer
    checkoutId={checkoutId || null}
    lines={checkout?.lines ?? []}
    totalPrice={checkout?.totalPrice ?? null}  // LINE 16
    channel={channel}
/>
```

**Required Change:** Replace `checkout?.totalPrice` with `checkout?.totalGrossAmount` on line 16. The prop name `totalPrice` is an internal component prop and can optionally remain as-is (see Cross-Cutting Concerns, Section 8).

---

### 4.8 `src/ui/components/cart/cart-drawer.tsx` — Cart Drawer Component

**Severity:** Breaking  
**Layer:** Screen/UI  
**Context:** Client component that renders the cart drawer with total price display.

**Impacted Code:**

**Interface definition (line 105):**
```tsx
interface CartDrawerProps {
    checkoutId: string | null;
    lines: CartLine[];
    totalPrice: {         // LINE 105: internal prop name
        gross: {
            amount: number;
            currency: string;
        };
    } | null;
    channel: string;
}
```

**Destructuring and usage (lines 114, 119, 120):**
```tsx
export function CartDrawer({ checkoutId, lines, totalPrice, channel }: CartDrawerProps) {  // LINE 114
    // ...
    const subtotal = totalPrice?.gross.amount ?? 0;       // LINE 119
    const currency = totalPrice?.gross.currency ?? localeConfig.fallbackCurrency;  // LINE 120
```

**Required Change:** The `totalPrice` prop name in `CartDrawerProps` is an **internal** prop name, not directly from the GraphQL field. Two options:
1. **Option A (recommended):** Keep `CartDrawerProps.totalPrice` as-is. Only update the **wrapper** (`cart-drawer-wrapper.tsx` line 16) to pass `checkout?.totalGrossAmount`. No changes needed in this file.
2. **Option B (consistency):** Rename the prop to `totalGrossAmount` throughout — but this requires changing the interface (line 105), destructuring (line 114), and all usages (lines 119, 120). This is optional.

---

### 4.9 `src/app/[channel]/(main)/cart/page.tsx` — Cart Page

**Severity:** Breaking  
**Layer:** Screen/UI  
**Context:** `CartContent` async component renders the full cart page with total.

**Impacted Code (line 107):**
```tsx
<div className="font-medium text-neutral-900">
    {formatMoney(checkout.totalPrice.gross.amount, checkout.totalPrice.gross.currency)}
</div>
```

**Required Change:** Replace `checkout.totalPrice` with `checkout.totalGrossAmount` on line 107 (both occurrences on the same line).

**Unimpacted in same file:** Line 87 (`item.totalPrice.gross.amount`) accesses CheckoutLine `totalPrice` — NOT affected.

---

### 4.10 Codegen Pipeline Impact

**Severity:** Requires Regeneration  
**Layer:** Shared Types (Generated Code)

Two codegen pipelines generate TypeScript types from the Saleor GraphQL schema:

| Pipeline | Config File | Output | Command | Generated Types Affected |
|----------|-------------|--------|---------|-------------------------|
| Storefront | `.graphqlrc.ts` | `src/gql/` | `pnpm run generate` | `CheckoutCreateMutation`, `CheckoutFindQuery`, `CheckoutLinesUpdateMutation` |
| Checkout | `src/checkout/graphql/codegen.ts` | `src/checkout/graphql/generated/index.ts` | `pnpm run generate:checkout` | `CheckoutFragmentFragment`, `CheckoutQuery`, all mutation types |

**Note:** The generated directories (`src/gql/` and `src/checkout/graphql/generated/`) do not exist in the repository (they are generated at build time via `predev`/`prebuild` scripts). They will automatically reflect the GraphQL query changes once:
1. The `.graphql` files are updated to use `totalGrossAmount`
2. The Saleor API schema is updated
3. `pnpm run generate:all` is executed

**`src/lib/checkout.ts`** imports `CheckoutFindDocument` and `CheckoutCreateDocument` from `@/gql/graphql`. The returned data shape will change (the field will be named `totalGrossAmount` instead of `totalPrice` on the Checkout object). All consumers of `Checkout.find()` and `Checkout.create()` will be affected — but these are the same components already listed in the breaking changes above.

---

### 4.11 Reference Code and Documentation

**Severity:** Requires Update (non-breaking)  
**Layer:** Documentation

These files are **not compiled** (excluded from tsconfig or in documentation directories) and will not cause build failures. However, they should be updated for accuracy.

| File | Lines | Content |
|------|-------|---------|
| `src/_reference/.../stripeComponent.tsx` | 67-68 | `checkout.totalPrice.gross.amount` and `.currency` |
| `src/_reference/.../stripeForm.tsx` | 60 | `checkout.totalPrice.gross.amount` |
| `src/_reference/.../useAdyenDropin.ts` | 52, 266, 284 | Destructured `totalPrice` from checkout, `totalPrice.gross.amount` |
| `skills/.../checkout-management.md` | 120, 157 | Code examples with `checkout.totalPrice.gross.amount` and GraphQL query with `totalPrice` |
| `skills/.../AGENTS.md` | 1665, 1702 | Code examples with `checkout.totalPrice.gross.amount` and GraphQL query with `totalPrice` |

---

## 5. Effort Estimate

| Metric | Count |
|--------|-------|
| Files requiring manual changes (hand-written code) | 9 |
| Files requiring regeneration | 2 directories |
| Files requiring documentation updates | 5 |
| Breaking changes in hand-written code | 13 individual usages |
| Total find-and-replace operations | ~15-20 |
| **Estimated Effort** | **Low** |

### Effort Breakdown

| Task | Files | Operations | Estimated Time |
|------|-------|-----------|---------------|
| Update `.graphql` files | 4 | 4 renames | 5 minutes |
| Regenerate TypeScript types | 2 pipelines | 1 command (`pnpm run generate:all`) | 2 minutes |
| Update TypeScript/React components | 5 | ~10 find-and-replace | 15 minutes |
| Update reference code | 3 | ~6 find-and-replace | 10 minutes |
| Update documentation | 2 | ~4 find-and-replace | 5 minutes |
| End-to-end testing | — | Checkout flow + cart | 30 minutes |
| **Total** | **14 files + 2 dirs** | **~25 operations** | **~1 hour** |

---

## 6. Migration Recommendations

### 6.1 Order of Operations

The migration MUST be coordinated with the Saleor Core API deployment:

```
┌─────────────────────────────────────────────────────────┐
│ PHASE 1: Prepare changes (BEFORE Saleor API deploys)    │
│                                                         │
│ 1. Create a branch with all storefront changes          │
│ 2. Update 4 .graphql files                              │
│ 3. Update 5 TypeScript/React component files            │
│ 4. Update 3 reference code files                        │
│ 5. Update 2 documentation files                         │
│ 6. Do NOT regenerate types yet (schema hasn't changed)  │
│ 7. PR ready, awaiting Saleor API deployment             │
├─────────────────────────────────────────────────────────┤
│ PHASE 2: Coordinated deployment                         │
│                                                         │
│ 1. Saleor Core API deploys the schema change            │
│ 2. Run `pnpm run generate:all` against updated API      │
│ 3. Verify generated types reflect `totalGrossAmount`    │
│ 4. Run full test suite                                  │
│ 5. Deploy storefront                                    │
└─────────────────────────────────────────────────────────┘
```

> **⚠️ Critical:** There will be a brief window of downtime between when the Saleor API deploys (removing `totalPrice`) and when the storefront deploys (using `totalGrossAmount`). During this window, checkout and cart pages will fail. To minimize this, deploy the storefront **immediately** after the Saleor API.

> **💡 Alternative:** If the Saleor Core API supports a deprecation period where **both** `totalPrice` and `totalGrossAmount` are available simultaneously, the storefront can be updated and deployed first, and the old field removed later. This is the recommended approach for zero-downtime migration.

### 6.2 Step-by-Step Migration

1. **Update GraphQL operations** (4 files):
   - `src/checkout/graphql/checkout.graphql:83` — `totalPrice` → `totalGrossAmount`
   - `src/graphql/CheckoutCreate.graphql:40` — `totalPrice` → `totalGrossAmount`
   - `src/graphql/CheckoutFind.graphql:65` — `totalPrice` → `totalGrossAmount`
   - `src/graphql/CheckoutLinesUpdate.graphql:15` — `totalPrice` → `totalGrossAmount`

2. **Regenerate types** (after Saleor API is updated):
   ```bash
   pnpm run generate:all
   ```

3. **Update TypeScript components** (5 files):
   - `src/checkout/views/saleor-checkout/order-summary.tsx` — 3 replacements (lines 70, 73, 75)
   - `src/checkout/views/saleor-checkout/payment-step.tsx` — 1 replacement (line 147)
   - `src/ui/components/cart/cart-drawer-wrapper.tsx` — 1 replacement (line 16)
   - `src/ui/components/cart/cart-drawer.tsx` — Optionally rename `CartDrawerProps.totalPrice` prop for consistency
   - `src/app/[channel]/(main)/cart/page.tsx` — 1 replacement (line 107, both occurrences)

4. **Update reference code** (3 files):
   - `src/_reference/.../stripeComponent.tsx` — 2 replacements
   - `src/_reference/.../stripeForm.tsx` — 1 replacement
   - `src/_reference/.../useAdyenDropin.ts` — 3 replacements

5. **Update documentation** (2 files):
   - `skills/.../checkout-management.md` — 2 replacements
   - `skills/.../AGENTS.md` — 2 replacements

6. **Test the checkout flow end-to-end:**
   - Create a new checkout → verify total displays correctly
   - Add/update line items → verify total updates
   - Proceed through payment step → verify total on pay button
   - Verify cart drawer displays correct total
   - Verify cart page displays correct total

### 6.3 Automation Possibilities

- **Simple find-and-replace codemod** could handle most changes:
  ```bash
  # For .graphql files (Checkout-level only — be careful not to change line-level):
  # Manual review needed — cannot blindly replace all `totalPrice` occurrences

  # For .tsx/.ts files (Checkout-level accesses):
  # Search for: checkout.totalPrice  or  checkout?.totalPrice
  # Replace with: checkout.totalGrossAmount  or  checkout?.totalGrossAmount
  ```
- **Codegen is fully automated:** `pnpm run generate:all` handles all type regeneration
- **⚠️ Warning:** Do NOT use a global find-and-replace for `totalPrice` → `totalGrossAmount`. This would incorrectly rename `CheckoutLine.totalPrice` and `OrderLine.totalPrice` references which are NOT being changed.

### 6.4 Test Files That Need Updates

No dedicated test files were found referencing `Checkout.totalPrice`. The project uses `vitest` but the test files in the grepped results do not appear to directly mock or assert on `checkout.totalPrice`. End-to-end testing of the checkout flow is recommended.

### 6.5 Deployment Coordination

- **Saleor Core API** must deploy first (or simultaneously with the storefront)
- **Storefront** should be deployed immediately after the API
- If the Saleor Core API provides a **deprecation period** (both field names valid), the storefront can be updated independently with no coordination required
- **No database migrations** needed on the storefront side
- **No environment variable changes** needed

---

## 7. Unimpacted Areas

The following files and references use `totalPrice` but are **NOT affected** by this change because they reference the field on **different GraphQL types** (`CheckoutLine` or `OrderLine`), not the `Checkout` type being renamed:

### 7.1 CheckoutLine.totalPrice (NOT renamed)

| File | Line | Context | Reason |
|------|------|---------|--------|
| `src/checkout/graphql/checkout.graphql` | 109 | `CheckoutLineFragment on CheckoutLine` | Different type: `CheckoutLine.totalPrice` is not renamed |
| `src/graphql/CheckoutCreate.graphql` | 9 | Inside `lines { ... }` | Selecting `totalPrice` on checkout line items, not checkout itself |
| `src/graphql/CheckoutFind.graphql` | 8 | Inside `lines { ... }` | Selecting `totalPrice` on checkout line items, not checkout itself |
| `src/graphql/CheckoutLinesUpdate.graphql` | 8 | Inside `lines { ... }` | Selecting `totalPrice` on checkout line items, not checkout itself |
| `src/checkout/views/saleor-checkout/order-summary.tsx` | 64 | `line.totalPrice?.gross?.amount` | Accesses line-item total, not checkout total |
| `src/ui/components/cart/cart-drawer.tsx` | 19 | `CartLine` interface `totalPrice` | Local interface for line-item data shape |
| `src/ui/components/cart/cart-drawer.tsx` | 297 | `line.totalPrice.gross.amount` | Renders per-line-item price in cart drawer |
| `src/app/[channel]/(main)/cart/page.tsx` | 87 | `item.totalPrice.gross.amount` | Renders per-line-item price in cart page |

### 7.2 OrderLine.totalPrice (NOT renamed)

| File | Line | Context | Reason |
|------|------|---------|--------|
| `src/checkout/graphql/order.graphql` | 22 | `OrderLineFragment on OrderLine` | Different type: `OrderLine.totalPrice` is not renamed |
| `src/checkout/views/saleor-checkout/order-summary.tsx` | 94 | `line.totalPrice?.gross?.amount` in `extractOrderData()` | Accesses order line-item total, not checkout total |

### 7.3 Order.total (different field entirely)

The `OrderFragment` in `src/checkout/graphql/order.graphql` uses `total` (not `totalPrice`) on the `Order` type. This is a completely different field and is unaffected.

### 7.4 Root AGENTS.md

The `AGENTS.md` file at the repository root does **not** contain any `totalPrice` references and is unaffected.

---

## 8. Cross-Cutting Concerns

### 8.1 Internal Prop Name Propagation

The `CartDrawer` component (in `src/ui/components/cart/cart-drawer.tsx`) receives checkout's total price via a prop named `totalPrice` (defined in the `CartDrawerProps` interface at line 105). This prop name is an **internal API** of the component, not directly derived from the GraphQL field name.

**Recommendation:** When updating `cart-drawer-wrapper.tsx` to pass `checkout?.totalGrossAmount`, you have two options:
1. **Keep the internal prop name as `totalPrice`** — simpler change, only wrapper needs updating
2. **Rename to `totalGrossAmount`** throughout — more consistent but more changes

Option 1 is recommended for minimal diff. The prop name can be cleaned up in a follow-up PR.

### 8.2 No Re-exports to Downstream Consumers

This storefront repository is a **leaf consumer** — it does not export any types, APIs, or packages that other repositories consume. The `totalPrice` → `totalGrossAmount` change does **not propagate** further downstream.

### 8.3 No Shared Infrastructure Concerns

- **No shared databases** — the storefront is a frontend-only application
- **No message queues** — communication is solely via GraphQL API
- **No shared configuration** — the `NEXT_PUBLIC_SALEOR_API_URL` environment variable does not need to change
- **No webhooks** affected — the storefront does not receive webhooks with `totalPrice` field

### 8.4 CI/CD Pipeline Consideration

The GitHub Actions workflows (`.github/workflows/update_types.yml`) may need attention:
- If the CI pipeline runs codegen as part of the build, it will fail if `.graphql` files reference `totalPrice` but the Saleor API has already renamed it to `totalGrossAmount`
- Ensure the storefront code changes are merged **at the same time** or **immediately after** the Saleor API schema update

### 8.5 `subtotalPrice` field

Note that the source change plan renames `totalPrice` to `totalGrossAmount` but does NOT mention `subtotalPrice`. The `subtotalPrice` field on `Checkout` (used in `checkout.graphql:96` and `order-summary.tsx:71`) is **not affected** by this change.

---

*Generated by Consumer Impact Scan — Analysis Date: 2026-04-27*

---

