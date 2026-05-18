# Change Impact Analysis Toolkit

A two-phase static analysis tool that determines how a proposed change in a **source repository** will affect **consumer repositories** downstream. Powered by [ATX](https://docs.aws.amazon.com/transform/latest/userguide/what-is.html) (AWS Transform Custom) for intelligent code analysis and natural-language transformation definitions.

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Phase 1: Source Analysis                      │
│                                                                     │
│  Change Request ──► Source Repo ──► ATX Transform ──► Outputs:      │
│                                                       • SOURCE_CHANGE_PLAN.md
│                                                       • EXTERNAL_SURFACE.json
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Phase 2: Consumer Impact Scanning                  │
│                                                                     │
│  For each consumer repo:                                            │
│    1. Clone repo                                                    │
│    2. Grep pre-filter (fast symbol matching)                        │
│    3. ATX Transform (deep analysis) ──► IMPACT_REPORT.md            │
│                                                                     │
│  Finally: Consolidate all reports into one document                 │
└─────────────────────────────────────────────────────────────────────┘
```

**Phase 1** analyzes the source repository to identify all changes required by a change request, classifies them as internal vs. externally-visible, and produces a machine-readable list of affected public symbols.

**Phase 2** clones each consumer repository, runs a fast grep pre-filter using the symbols from Phase 1, then executes a deep ATX analysis on repos with potential matches. Each consumer gets an impact report detailing exactly which files, lines, and code references need to change.

## Prerequisites

### Required Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `git` | Clone repositories | [git-scm.com](https://git-scm.com/downloads) |
| `atx` | Execute transformation definitions | See below |
| `python3` | JSON manipulation and context truncation | Pre-installed on most systems |
| `bash 4.3+` | Script execution (uses `wait -n`) | Default on Linux; `brew install bash` on macOS |

### Installing the ATX CLI

The `atx` CLI (AWS Transform Custom) is the engine that executes the transformation definitions. To set it up:

1. **Install the CLI** — Follow the [AWS Transform Custom documentation](https://docs.aws.amazon.com/transform/latest/userguide/what-is.html) to download and install the `atx` binary.

2. **Authenticate with AWS** — ATX requires valid AWS credentials. Configure them via:
   ```bash
   aws configure
   # or export environment variables:
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_REGION=us-east-1
   ```

3. **Verify the installation**:
   ```bash
   atx --version
   ```

### ATX Concepts Used by This Script

- **Transformation Definition** — A natural-language markdown file that instructs ATX what analysis to perform and what outputs to produce. This project includes two definitions (one per phase) in `transformation-def/`.

- **`atx custom def save-draft`** — Registers a transformation definition in the ATX registry and returns a version identifier. The script does this automatically if you don't provide `--source-tv` or `--consumer-tv`.

- **`atx custom def exec`** — Executes a registered transformation against a local repository. Key flags used:
  - `-p <path>` — path to the cloned repo
  - `-n <name>` — registered definition name
  - `--tv <version>` — pin to a specific definition version
  - `-g "file://<path>"` — pass additional context via a JSON file
  - `-x` — execute mode
  - `-t` — terminal output

- **`additionalPlanContext`** — A string (max 4096 chars) passed to ATX providing runtime context. This script uses it to pass the change request description and pre-filter results to each transform execution.

### Verify All Prerequisites

```bash
git --version
atx --version
python3 --version
bash --version   # Should be 4.3+ for full parallelism support
```

## Quick Start

### Understanding the Provider/Consumer Model

This tool analyzes the ripple effect of a change in a **provider** (source) repository on its **consumer** repositories:

- **Provider repo** — The upstream repository where the change originates. It exposes APIs, types, schemas, or packages that others depend on.
- **Consumer repos** — Downstream repositories that import, call, or reference the provider's public surface.

### Sample Repos for Testing

This project includes a ready-to-use example based on [Saleor](https://github.com/saleor) — an open-source e-commerce platform with a clear provider/consumer architecture:

| Role | Repository | Relationship |
|------|-----------|--------------|
| **Provider** | [saleor/saleor](https://github.com/saleor/saleor) | Core backend — exposes a GraphQL API schema |
| Consumer | [saleor/saleor-dashboard](https://github.com/saleor/saleor-dashboard) | Admin UI — queries the GraphQL API heavily |
| Consumer | [saleor/apps](https://github.com/saleor/apps) | Marketplace apps — use GraphQL fragments and SDK |
| Consumer | [saleor/storefront](https://github.com/saleor/storefront) | Customer-facing storefront — queries checkout, products |
| Consumer | [saleor/configurator](https://github.com/saleor/configurator) | Configuration tool — uses GraphQL schema |
| Consumer | [saleor/awesome-saleor](https://github.com/saleor/awesome-saleor) | Community resource list — references docs/APIs |
| Consumer | [saleor/saleor-graphql-playground](https://github.com/saleor/saleor-graphql-playground) | GraphQL explorer — uses schema introspection |

This is a good test case because:
- The provider exposes a well-defined GraphQL schema
- Consumers reference specific field names in `.graphql` files, making grep pre-filtering effective
- The ecosystem has multiple repos with varying levels of coupling (tight for dashboard, loose for awesome-saleor)

### Running the Example

```bash
# 1. Define your change request
cat > change-request.md << 'EOF'
# Change Request: Rename totalPrice to totalGrossAmount in Checkout Type

## Summary
Rename the `totalPrice` field to `totalGrossAmount` in the `Checkout` GraphQL type.

## Details
- **Target type**: `Checkout` (GraphQL type)
- **Current field name**: `totalPrice`
- **New field name**: `totalGrossAmount`
- **Scope**: Breaking change to the GraphQL schema.
EOF

# 2. List consumer repos to scan
cat > consumer-repos.txt << 'EOF'
https://github.com/saleor/saleor-dashboard
https://github.com/saleor/apps
https://github.com/saleor/storefront
https://github.com/saleor/configurator
https://github.com/saleor/awesome-saleor
https://github.com/saleor/saleor-graphql-playground
EOF

# 3. Run the analysis
./run-impact-analysis.sh \
  --source https://github.com/saleor/saleor \
  --change-file change-request.md \
  --repo-file consumer-repos.txt \
  --shallow -j 4
```

### Other Change Requests to Try

You can test different types of changes against the same ecosystem:

| Change Type | Example Change Request |
|-------------|----------------------|
| Field removal | "Remove the `discount` field from the `OrderLine` GraphQL type" |
| Type rename | "Rename the `Warehouse` type to `FulfillmentCenter`" |
| Argument addition | "Add a required `channel` argument to the `products` query" |
| Deprecation | "Deprecate the `checkoutCreate` mutation in favor of `checkoutInitialize`" |

## Usage

```
Usage: run-impact-analysis.sh [OPTIONS] [CONSUMER_REPO ...]
```

### Options

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--source <url>` | `-s` | Source repository URL (required) | — |
| `--change <text>` | `-c` | Change request description (inline) | — |
| `--change-file <path>` | `-C` | File containing the change request | — |
| `--repo-file <path>` | `-f` | File with consumer repo URLs (one per line) | — |
| `--workspace <path>` | `-w` | Workspace root directory | `./workspace` |
| `--parallel <n>` | `-j` | Max parallel ATX jobs (1–10) | `1` |
| `--shallow` | | Use shallow clones (`--depth 1`) for speed | off |
| `--skip-source` | | Skip Phase 1, reuse existing outputs | off |
| `--skip-no-matches` | | Skip ATX for repos with no grep matches | off |
| `--tv <version>` | | Pin both transforms to a specific version | auto-register |
| `--source-tv <version>` | | Pin source-analysis transform version | auto-register |
| `--consumer-tv <version>` | | Pin consumer-impact transform version | auto-register |
| `--source-def <name>` | | Source analysis transform name | `source-analysis` |
| `--consumer-def <name>` | | Consumer impact transform name | `consumer-impact` |
| `--help` | `-h` | Show help message | — |

Consumer repos can be specified as positional arguments, via `--repo-file`, or both.

### Examples

```bash
# Full two-phase analysis with parallelism and shallow clones
./run-impact-analysis.sh \
  --source https://github.com/saleor/saleor \
  --change-file change-request.md \
  --repo-file consumer-repos.txt \
  --shallow --skip-no-matches -j 4

# Skip source analysis (reuse previous Phase 1 outputs)
./run-impact-analysis.sh \
  --source https://github.com/saleor/saleor \
  --change-file change-request.md \
  --repo-file consumer-repos.txt \
  --skip-source -j 4

# Analyze a single consumer repo
./run-impact-analysis.sh \
  --source https://github.com/saleor/saleor \
  --change "Rename Checkout.totalPrice to Checkout.totalGrossAmount" \
  https://github.com/saleor/saleor-dashboard
```

## Outputs

All outputs are written to `<workspace>/results/`:

```
workspace/results/
├── CONSOLIDATED_IMPACT_REPORT.md          # Combined report for all consumers
├── saleor/
│   ├── SOURCE_CHANGE_PLAN.md              # What changes in the source repo
│   └── EXTERNAL_SURFACE.json             # Machine-readable affected symbols
├── saleor-dashboard/
│   └── IMPACT_REPORT.md                   # Impact details for this consumer
├── apps/
│   └── IMPACT_REPORT.md
└── storefront/
    └── IMPACT_REPORT.md
```

### SOURCE_CHANGE_PLAN.md

Lists every modification needed in the source repo, classified by layer (API, Service Logic, Database, Shared Types, etc.) with before/after details.

### EXTERNAL_SURFACE.json

Machine-readable JSON listing externally-visible changes with searchable symbols. Used by the grep pre-filter to quickly identify affected consumer repos. Contains:
- Changed symbols and search patterns
- File type patterns for targeted searching
- Dependency indicators (package names, API endpoints, queue topics)

### IMPACT_REPORT.md (per consumer)

Detailed analysis of each consumer repo including:
- Dependency relationship and version
- Every file/line referencing changed symbols
- Impact severity (Breaking, Behavioral, Requires Update, No Impact)
- Exact code changes needed
- Effort estimate and migration recommendations

### CONSOLIDATED_IMPACT_REPORT.md

Combines all individual reports into a single document with metadata, summary statistics, and per-repo sections.

## Performance Optimizations

| Flag | Effect | Tradeoff |
|------|--------|----------|
| `--shallow` | Clones with `--depth 1` (no git history) | Cannot analyze git blame or history |
| `-j 4` | Parallel cloning, pre-filtering, and ATX execution | Higher memory/CPU usage |
| `--skip-no-matches` | Skips ATX for repos where grep found no symbols | May miss indirect dependencies (REST calls via env vars, SDK wrappers) |
| `--skip-source` | Reuses existing Phase 1 outputs | Must have run Phase 1 previously |

For a typical run with 6 consumer repos, `--shallow -j 4` reduces total time from ~15 minutes to ~4 minutes.

## Project Structure

```
.
├── run-impact-analysis.sh                          # Main orchestration script
├── transformation-def/
│   ├── source-analysis/
│   │   └── transformation_definition.md            # Phase 1: ATX instructions
│   └── consumer-impact/
│       └── transformation_definition.md            # Phase 2: ATX instructions
├── change-request.md                               # Your change request (input)
├── consumer-repos.txt                              # Consumer repo list (input)
├── workspace/                                      # Runtime workspace (gitignored)
│   ├── repos/                                      # Cloned repositories
│   ├── prefilter/                                  # Grep pre-filter results
│   ├── logs/                                       # Per-worker ATX logs
│   └── results/                                    # Final output reports
└── README.md
```

## Transformation Definitions

The analysis logic is defined in natural-language markdown files that instruct ATX what to do:

### `transformation-def/source-analysis/transformation_definition.md`

Instructs ATX to:
1. Parse the change request
2. Walk the source codebase to find all required modifications
3. Classify each change by layer
4. Separate internal-only changes from externally-visible ones
5. Produce `SOURCE_CHANGE_PLAN.md` and `EXTERNAL_SURFACE.json`

### `transformation-def/consumer-impact/transformation_definition.md`

Instructs ATX to:
1. Detect the dependency relationship with the source repo
2. Scan for all usages of changed symbols
3. Determine impact severity per usage
4. Produce `IMPACT_REPORT.md` with exact code changes needed

You can customize these definitions to focus on different aspects of analysis or adjust the output format.

## Limitations

- **Externalized endpoints**: If a consumer calls the source API via a URL stored entirely in an environment variable (not in the code repo), static analysis cannot detect the dependency.
- **Generated code in `.gitignore`**: Code generated at build time (e.g., GraphQL codegen output) may not be present in the repo for analysis.
- **SDK indirection**: If consumers use an SDK that wraps the source API, the actual field names may only appear inside `node_modules` (not scanned).
- **ATX context limit**: The `additionalPlanContext` field has a 4096-character limit. For very large source change plans, context is truncated.
- **`wait -n` requires Bash 4.3+**: macOS ships with Bash 3.2 by default. Install a newer version via `brew install bash` or the script degrades gracefully (less precise parallelism throttling).

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | All analyses succeeded |
| `1` | Fatal error (missing prerequisites, bad arguments, source clone failure) |
| `2` | Partial failure (some consumer analyses failed, others succeeded) |

## License

[MIT](LICENSE)
