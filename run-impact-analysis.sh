#!/usr/bin/env bash
# ==============================================================================
# run-impact-analysis.sh
# ==============================================================================
#
# PURPOSE:
#   This script performs a two-phase "Change Impact Analysis" to determine how
#   a proposed change in a SOURCE repository (e.g. saleor/saleor) will affect
#   one or more CONSUMER repositories (e.g. saleor-dashboard, apps, storefront).
#
# HIGH-LEVEL WORKFLOW:
#   Phase 1 — Source Analysis:
#     1. Clone the source repository.
#     2. Register (or reuse) a "source-analysis" transformation definition with ATX.
#     3. Run the ATX transform on the source repo. This produces:
#        - SOURCE_CHANGE_PLAN.md  — a structured description of what changes.
#        - EXTERNAL_SURFACE.json  — symbols/endpoints exposed to consumers.
#
#   Phase 2 — Consumer Impact Scanning:
#     1. Clone all consumer repositories.
#     2. Pre-filter each consumer repo with grep using symbols from EXTERNAL_SURFACE.json
#        to quickly identify repos/files that are likely affected (avoids expensive full scans).
#     3. Register (or reuse) a "consumer-impact" transformation definition with ATX.
#     4. Run the ATX transform on each consumer repo (in parallel batches).
#        This produces an IMPACT_REPORT.md per consumer repo.
#     5. Consolidate all reports into a single CONSOLIDATED_IMPACT_REPORT.md.
#
# DEPENDENCIES:
#   - git       : for cloning repositories
#   - atx       : the transformation execution engine (ATX CLI)
#   - python3   : used for JSON manipulation and context truncation
#
# OUTPUTS (written to <workspace>/results/):
#   - <source>/SOURCE_CHANGE_PLAN.md       — what the source change entails
#   - <source>/EXTERNAL_SURFACE.json       — public symbols affected
#   - <consumer>/IMPACT_REPORT.md          — per-consumer impact details
#   - CONSOLIDATED_IMPACT_REPORT.md        — combined summary of all impacts
#
# EXIT CODES:
#   0 — all analyses succeeded
#   1 — fatal error (missing prereqs, bad args, clone failure, etc.)
#   2 — partial failure (some consumer analyses failed but others succeeded)
#
# ==============================================================================

# Fail immediately on errors, undefined variables, or pipe failures.
set -euo pipefail

# ─── Logging helpers ───────────────────────────────────────────────────────────
# Simple tagged logging functions for consistent output formatting.
# log_error writes to stderr so it can be separated from normal output.
log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# ─── Prerequisites ─────────────────────────────────────────────────────────────
# Checks that all required external tools (git, atx) are available on PATH.
# Exits with code 1 if any are missing, after reporting which ones.
validate_prerequisites() {
  local missing=0
  if ! command -v git &>/dev/null; then
    log_error "Required tool 'git' is not installed or not on PATH."
    missing=1
  fi
  if ! command -v atx &>/dev/null; then
    log_error "Required tool 'atx' is not installed or not on PATH."
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

# ─── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage: run-impact-analysis.sh [OPTIONS] [CONSUMER_REPO ...]

Two-phase change impact analysis: analyze source repo for changes,
then scan consumer repos for downstream impact.

Phase 1: Runs source-analysis transform on the source repo to identify
         all changes and classify them as internal vs external.
Phase 2: Pre-filters consumer repos with grep, then runs consumer-impact
         transform on repos with potential matches.

Options:
  -s, --source <url>           Source repository URL (required)
  -c, --change <description>   Change request description (required, or use --change-file)
  -C, --change-file <path>     File containing the change request description
  -f, --repo-file <path>       File containing consumer repo URLs (one per line)
  --source-def <name>          Source analysis transform name (default: source-analysis)
  --consumer-def <name>        Consumer impact transform name (default: consumer-impact)
  --tv <version>               Transformation version for both transforms
  --source-tv <version>        Transformation version for source analysis only
  --consumer-tv <version>      Transformation version for consumer impact only
  -w, --workspace <path>       Workspace root directory (default: ./workspace)
  -j, --parallel <n>           Max parallel consumer ATX jobs (default: 1, max: 10)
  --skip-source                Skip source analysis (reuse existing SOURCE_CHANGE_PLAN.md)
  --skip-no-matches            Skip ATX for repos where grep pre-filter found no matches
  --shallow                    Use shallow clones (--depth 1) for faster cloning
  -h, --help                   Show this help message

Consumer repos can be specified as positional args, via --repo-file, or both.

Examples:
  # Full two-phase analysis
  run-impact-analysis.sh \
    --source https://github.com/saleor/saleor \
    --change-file change-request.md \
    --repo-file consumer-repos.txt \
    --source-tv <version> --consumer-tv <version>

  # Skip source analysis (already done), just scan consumers
  run-impact-analysis.sh \
    --source https://github.com/saleor/saleor \
    --change-file change-request.md \
    --repo-file consumer-repos.txt \
    --skip-source --consumer-tv <version>
EOF
}

# ─── Repo helpers ──────────────────────────────────────────────────────────────

# resolve_repo_url: Normalizes a repo identifier to a full URL.
# Accepts either a full URL (http/https) or a GitHub shorthand like "org/repo".
# Example: "saleor/saleor" → "https://github.com/saleor/saleor"
resolve_repo_url() {
  local id="$1"
  if [[ "$id" == http://* || "$id" == https://* ]]; then
    echo "$id"
  else
    echo "https://github.com/${id}"
  fi
}

# repo_name_from_url: Extracts the repository name from a URL.
# Strips the trailing ".git" if present.
# Example: "https://github.com/saleor/saleor-dashboard.git" → "saleor-dashboard"
repo_name_from_url() {
  basename "$1" .git
}

# clone_repo: Clones a repository with optional shallow clone support.
# Uses --depth 1 when SHALLOW_CLONE=true to skip full history (much faster).
# Parameters:
#   $1 - url       : the git URL to clone
#   $2 - dest_path : local destination path
# Returns 0 on success, 1 on failure.
clone_repo() {
  local url="$1"
  local dest_path="$2"
  local clone_args=(git clone)

  if [[ "$SHALLOW_CLONE" == true ]]; then
    clone_args+=(--depth 1 --single-branch)
  fi

  clone_args+=("$url" "$dest_path")
  "${clone_args[@]}" 2>&1
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
# Default values for all configurable parameters.
SOURCE_DEF="source-analysis"       # Name of the ATX transform definition for Phase 1
CONSUMER_DEF="consumer-impact"     # Name of the ATX transform definition for Phase 2
TRANSFORM_VERSION=""               # Shared version override for both transforms
SOURCE_TV=""                       # Version override specific to source-analysis
CONSUMER_TV=""                     # Version override specific to consumer-impact
WORKSPACE="./workspace"            # Root directory for cloned repos, logs, and results
REPO_FILE=""                       # Path to a file listing consumer repo URLs
SOURCE_REPO=""                     # URL or shorthand of the source repository
CHANGE_DESC=""                     # Inline change description text
CHANGE_FILE=""                     # Path to a file containing the change description
SKIP_SOURCE=false                  # If true, skip Phase 1 and reuse existing outputs
SKIP_NO_MATCHES=false              # If true, skip ATX for repos where grep found no matches
SHALLOW_CLONE=false                # If true, use --depth 1 for faster cloning
PARALLEL=1                         # Max number of concurrent consumer ATX jobs
CONSUMER_REPOS=()                  # Array of consumer repo identifiers (URLs or shorthands)

# parse_args: Processes all CLI arguments and populates the global config variables.
# Supports both flag-based options and positional arguments (treated as consumer repos).
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--source)        SOURCE_REPO="$2"; shift 2 ;;
      -c|--change)        CHANGE_DESC="$2"; shift 2 ;;
      -C|--change-file)   CHANGE_FILE="$2"; shift 2 ;;
      -f|--repo-file)     REPO_FILE="$2"; shift 2 ;;
      --source-def)       SOURCE_DEF="$2"; shift 2 ;;
      --consumer-def)     CONSUMER_DEF="$2"; shift 2 ;;
      --tv)               TRANSFORM_VERSION="$2"; shift 2 ;;
      --source-tv)        SOURCE_TV="$2"; shift 2 ;;
      --consumer-tv)      CONSUMER_TV="$2"; shift 2 ;;
      -w|--workspace)     WORKSPACE="$2"; shift 2 ;;
      -j|--parallel)      PARALLEL="$2"; shift 2 ;;
      --skip-source)      SKIP_SOURCE=true; shift ;;
      --skip-no-matches)  SKIP_NO_MATCHES=true; shift ;;
      --shallow)          SHALLOW_CLONE=true; shift ;;
      -h|--help)          usage; exit 0 ;;
      -*)                 log_error "Unknown option: $1"; usage; exit 1 ;;
      *)                  CONSUMER_REPOS+=("$1"); shift ;;
    esac
  done

  # If a shared --tv was given but no specific --source-tv / --consumer-tv,
  # propagate the shared version to both.
  if [[ -z "$SOURCE_TV" && -n "$TRANSFORM_VERSION" ]]; then
    SOURCE_TV="$TRANSFORM_VERSION"
  fi
  if [[ -z "$CONSUMER_TV" && -n "$TRANSFORM_VERSION" ]]; then
    CONSUMER_TV="$TRANSFORM_VERSION"
  fi
}

# ─── Load repos from file ─────────────────────────────────────────────────────
# Reads consumer repo URLs from a text file (one per line).
# Blank lines and lines starting with '#' are treated as comments and skipped.
# Each valid line is appended to the CONSUMER_REPOS array.
load_repo_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_error "Repo file not found: $file"
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(echo "$line" | xargs)"
    [[ -z "$line" || "$line" == \#* ]] && continue
    CONSUMER_REPOS+=("$line")
  done < "$file"
}

# ─── Build ATX command ─────────────────────────────────────────────────────────
# Constructs the ATX CLI command array for executing a transformation.
# Parameters:
#   $1 - repo_path : local filesystem path to the cloned repo
#   $2 - def_name  : name of the registered transformation definition
#   $3 - tv        : transformation version (can be empty)
#   $4 - context   : additional plan context string passed via -g flag
# The -x flag enables execution mode; -t enables terminal output.
build_atx_cmd() {
  local repo_path="$1"
  local def_name="$2"
  local tv="$3"
  local context="$4"

  local cmd=(atx custom def exec -p "$repo_path" -n "$def_name")
  [[ -n "$tv" ]] && cmd+=(--tv "$tv")
  cmd+=(-g "additionalPlanContext=${context}" -x -t)
  echo "${cmd[@]}"
}

# ─── Pre-filter consumer repo with grep ───────────────────────────────────────
# Performs a fast grep-based scan of a consumer repo to identify files that
# reference symbols from the source repo's external surface.
#
# This is an optimization step: rather than running the expensive ATX transform
# on every file, we first narrow down to files that contain relevant symbols
# (function names, API endpoints, package names, etc.).
#
# Parameters:
#   $1 - repo_path            : path to the cloned consumer repo
#   $2 - external_surface_file: path to EXTERNAL_SURFACE.json from Phase 1
#   $3 - output_file          : where to write the list of matching files
#
# Output file contents:
#   - "NO_PREFILTER" if no symbols were available to search for
#   - "NO_MATCHES"   if grep found zero matching files
#   - Otherwise, a newline-separated list of matching file paths
prefilter_repo() {
  local repo_path="$1"
  local external_surface_file="$2"
  local output_file="$3"

  # Extract search symbols from EXTERNAL_SURFACE.json using Python.
  # The JSON contains:
  #   - all_search_symbols: array of function/type/field names to search for
  #   - dependency_indicators: object with package_names, api_endpoints,
  #     queue_topics, shared_db_tables — all potential coupling points.
  # We combine all of these into a single list of grep patterns.
  local symbols
  if [[ -f "$external_surface_file" ]]; then
    # Parse all_search_symbols array from JSON
    symbols=$(python3 -c "
import json, sys
try:
    with open('$external_surface_file') as f:
        data = json.load(f)
    symbols = data.get('all_search_symbols', [])
    # Also add dependency indicators
    dep = data.get('dependency_indicators', {})
    symbols += dep.get('package_names', [])
    symbols += dep.get('api_endpoints', [])
    symbols += dep.get('queue_topics', [])
    symbols += dep.get('shared_db_tables', [])
    # Deduplicate and filter empty
    symbols = list(set(s for s in symbols if s))
    print('\n'.join(symbols))
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || true
  fi

  if [[ -z "$symbols" || ! -f "$external_surface_file" ]]; then
    log_warn "No search symbols found — will run full ATX scan"
    echo "NO_PREFILTER" > "$output_file"
    return 0
  fi

  log_info "Pre-filtering with symbols: $(echo "$symbols" | tr '\n' ', ')"

  # Build a single extended-regex OR pattern from all symbols.
  # Special regex characters in symbol names are escaped first.
  local pattern
  pattern=$(echo "$symbols" | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd'|' -)

  # Run recursive grep across common source file types.
  # We search a broad set of extensions to catch usage in code, configs,
  # GraphQL schemas, protobuf definitions, and documentation.
  local matches
  matches=$(grep -rl --include="*.ts" --include="*.tsx" --include="*.js" \
    --include="*.jsx" --include="*.py" --include="*.java" --include="*.go" \
    --include="*.graphql" --include="*.gql" --include="*.json" \
    --include="*.yaml" --include="*.yml" --include="*.xml" \
    --include="*.toml" --include="*.cfg" --include="*.ini" \
    --include="*.proto" --include="*.md" \
    -E "$pattern" "$repo_path" 2>/dev/null || true)

  if [[ -z "$matches" ]]; then
    log_info "No matches found in grep pre-filter"
    echo "NO_MATCHES" > "$output_file"
  else
    local count
    count=$(echo "$matches" | wc -l | xargs)
    log_info "Grep pre-filter found $count files with potential matches"
    echo "$matches" > "$output_file"
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────────
# Orchestrates the entire two-phase analysis pipeline:
#   1. Parse arguments and validate inputs
#   2. Set up workspace directory structure
#   3. Auto-register ATX transformation definitions (if versions not provided)
#   4. Phase 1: Clone source repo → run source-analysis ATX transform
#   5. Phase 2: Clone consumers → grep pre-filter → run consumer-impact ATX transforms
#   6. Collect results, generate consolidated report, print summary
main() {
  parse_args "$@"
  validate_prerequisites

  # ── Validate all required inputs before doing any work ──
  if [[ -z "$SOURCE_REPO" ]]; then
    log_error "Source repository is required. Use --source <url>."
    usage; exit 1
  fi

  if [[ -n "$CHANGE_FILE" ]]; then
    if [[ ! -f "$CHANGE_FILE" ]]; then
      log_error "Change file not found: $CHANGE_FILE"
      exit 1
    fi
    CHANGE_DESC="$(cat "$CHANGE_FILE")"
  fi

  if [[ -z "$CHANGE_DESC" ]]; then
    log_error "Change description is required. Use --change <text> or --change-file <path>."
    usage; exit 1
  fi

  if [[ -n "$REPO_FILE" ]]; then
    load_repo_file "$REPO_FILE"
  fi

  if [[ ${#CONSUMER_REPOS[@]} -eq 0 ]]; then
    log_error "No consumer repositories specified."
    usage; exit 1
  fi

  # ── Validate parallelism is within bounds (1–10) ──
  if [[ "$PARALLEL" -lt 1 || "$PARALLEL" -gt 10 ]]; then
    log_error "--parallel must be between 1 and 10"
    exit 1
  fi

  # ── Create workspace directory structure ──
  # repos/      — cloned git repositories
  # prefilter/  — grep pre-filter results (one file per consumer repo)
  # logs/       — per-worker ATX execution logs and config files
  # results/    — final output reports (moved here after ATX completes)
  # status.log  — machine-readable status tracking (name|status|match_count)
  local repos_dir="${WORKSPACE}/repos"
  local prefilter_dir="${WORKSPACE}/prefilter"
  local logs_dir="${WORKSPACE}/logs"
  local results_dir="${WORKSPACE}/results"
  local status_file="${WORKSPACE}/status.log"
  mkdir -p "$repos_dir" "$prefilter_dir" "$logs_dir" "$results_dir"
  : > "$status_file"  # Truncate status file for a fresh run
  # Clear previous worker logs to avoid confusion with stale data
  rm -f "${logs_dir}"/*.log "${logs_dir}"/*-config.json

  # Resolve source repo
  local source_url
  source_url="$(resolve_repo_url "$SOURCE_REPO")"
  local source_name
  source_name="$(repo_name_from_url "$source_url")"
  local source_path="${repos_dir}/${source_name}"

  # ══════════════════════════════════════════════════════════════════════════
  # AUTO-REGISTER: Register transformation definitions if needed
  # ══════════════════════════════════════════════════════════════════════════
  # If no explicit --source-tv or --consumer-tv version was provided, the script
  # automatically registers the transformation definition from the local
  # transformation-def/ directory using `atx custom def save-draft`.
  # This creates a new draft version in the ATX registry and extracts the
  # version ID from the command output for use in subsequent exec calls.

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Register source-analysis transform if no version provided.
  # The definition directory contains a transformation_definition.md that
  # instructs ATX how to analyze the source repo for breaking changes.
  if [[ -z "$SOURCE_TV" && "$SKIP_SOURCE" != true ]]; then
    local source_def_dir="${script_dir}/transformation-def/source-analysis"
    if [[ -d "$source_def_dir" ]]; then
      log_info "Registering source-analysis transform..."
      local save_output
      save_output=$(atx custom def save-draft \
        -n "$SOURCE_DEF" \
        --description "Phase 1: Analyze source repo changes and classify internal vs external" \
        --sd "$source_def_dir" 2>&1) || {
        log_error "Failed to register source-analysis transform: $save_output"
        exit 1
      }
      # Extract version from output like: "✓ Saved a draft transformation 'source-analysis' with version 'abc123' in the registry"
      SOURCE_TV=$(echo "$save_output" | grep -oE "version '[^']+'" | head -1 | sed "s/version '//;s/'//")
      if [[ -n "$SOURCE_TV" ]]; then
        log_info "Registered source-analysis version: $SOURCE_TV"
      else
        log_warn "Could not extract version from save-draft output. ATX may use latest version."
        log_warn "Output was: $save_output"
      fi
    else
      log_error "Source analysis definition directory not found: $source_def_dir"
      exit 1
    fi
  fi

  # Register consumer-impact transform if no version provided.
  # This definition instructs ATX how to scan a consumer repo for references
  # to the changed symbols and produce an IMPACT_REPORT.md.
  if [[ -z "$CONSUMER_TV" ]]; then
    local consumer_def_dir="${script_dir}/transformation-def/consumer-impact"
    if [[ -d "$consumer_def_dir" ]]; then
      log_info "Registering consumer-impact transform..."
      local save_output
      save_output=$(atx custom def save-draft \
        -n "$CONSUMER_DEF" \
        --description "Phase 2: Scan consumer repo for impact from source changes" \
        --sd "$consumer_def_dir" 2>&1) || {
        log_error "Failed to register consumer-impact transform: $save_output"
        exit 1
      }
      CONSUMER_TV=$(echo "$save_output" | grep -oE "version '[^']+'" | head -1 | sed "s/version '//;s/'//")
      if [[ -n "$CONSUMER_TV" ]]; then
        log_info "Registered consumer-impact version: $CONSUMER_TV"
      else
        log_warn "Could not extract version from save-draft output. ATX may use latest version."
        log_warn "Output was: $save_output"
      fi
    else
      log_error "Consumer impact definition directory not found: $consumer_def_dir"
      exit 1
    fi
  fi

  # ══════════════════════════════════════════════════════════════════════════
  # PHASE 1: Source Analysis
  # ══════════════════════════════════════════════════════════════════════════
  # Analyzes the source repository to understand what is changing and
  # classify changes as internal (implementation detail) vs external
  # (public API surface that consumers depend on).
  # Produces:
  #   - SOURCE_CHANGE_PLAN.md  : human-readable plan of all changes
  #   - EXTERNAL_SURFACE.json  : machine-readable list of affected public symbols

  if [[ "$SKIP_SOURCE" == true ]]; then
    log_info "=== Phase 1: SKIPPED (--skip-source) ==="
    # Check both repo dir and results dir for existing outputs
    if [[ ! -f "${source_path}/SOURCE_CHANGE_PLAN.md" && ! -f "${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md" ]]; then
      log_error "Cannot skip source analysis: SOURCE_CHANGE_PLAN.md not found in repo or results"
      exit 1
    fi
    if [[ ! -f "${source_path}/EXTERNAL_SURFACE.json" && ! -f "${results_dir}/${source_name}/EXTERNAL_SURFACE.json" ]]; then
      log_warn "EXTERNAL_SURFACE.json not found — grep pre-filtering will be disabled"
    fi
  else
    log_info "════════════════════════════════════════════════════════════════"
    log_info "  PHASE 1: Source Repository Analysis"
    log_info "════════════════════════════════════════════════════════════════"

    # Clone source
    if [[ -d "$source_path" ]]; then
      log_info "Source repo already cloned: $source_name"
    else
      log_info "Cloning source repo $source_url"
      if ! clone_repo "$source_url" "$source_path"; then
        log_error "Failed to clone source repository: $source_url"
        exit 1
      fi
    fi

    # Run source analysis transform
    log_info "Running source analysis on: $source_name"
    log_info "Change request: $(echo "$CHANGE_DESC" | head -3)..."

    # Write config file for source analysis.
    # ATX accepts context via a JSON file referenced with "file://" prefix.
    # The config contains the change request description as additionalPlanContext.
    local source_config="${logs_dir}/${source_name}-source-config.json"
    python3 -c "
import json, sys
config = {'additionalPlanContext': sys.argv[1]}
with open(sys.argv[2], 'w') as f:
    json.dump(config, f)
" "$CHANGE_DESC" "$source_config"

    # Build and execute the ATX command for source analysis.
    # Flags: -p (project path), -n (definition name), --tv (version),
    #        -g (global context, file:// for JSON file), -x (execute), -t (terminal output)
    local src_cmd=(atx custom def exec -p "$source_path" -n "$SOURCE_DEF")
    if [[ -n "$SOURCE_TV" ]]; then
      src_cmd+=(--tv "$SOURCE_TV")
    fi
    src_cmd+=(-g "file://${source_config}" -x -t)

    if "${src_cmd[@]}" 2>&1; then
      log_info "Source analysis completed successfully."
    else
      log_error "Source analysis failed for $source_name."
      exit 1
    fi

    # Verify outputs
    if [[ ! -f "${source_path}/SOURCE_CHANGE_PLAN.md" ]]; then
      log_warn "SOURCE_CHANGE_PLAN.md not generated — ATX may have used a different output format"
    fi
    if [[ ! -f "${source_path}/EXTERNAL_SURFACE.json" ]]; then
      log_warn "EXTERNAL_SURFACE.json not generated — grep pre-filtering will be disabled"
    fi
  fi

  # Read source outputs for Phase 2 context.
  # The source change plan is passed to each consumer ATX run so it knows
  # what changed. We check both the results dir (if moved) and the repo dir.
  local source_plan=""
  local plan_file=""
  if [[ -f "${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md" ]]; then
    plan_file="${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md"
  elif [[ -f "${source_path}/SOURCE_CHANGE_PLAN.md" ]]; then
    plan_file="${source_path}/SOURCE_CHANGE_PLAN.md"
  fi
  if [[ -n "$plan_file" ]]; then
    source_plan="$(cat "$plan_file")"
    log_info "Loaded source change plan ($(wc -c < "$plan_file" | xargs) bytes)"
  fi

  local external_surface=""
  if [[ -f "${results_dir}/${source_name}/EXTERNAL_SURFACE.json" ]]; then
    external_surface="${results_dir}/${source_name}/EXTERNAL_SURFACE.json"
  elif [[ -f "${source_path}/EXTERNAL_SURFACE.json" ]]; then
    external_surface="${source_path}/EXTERNAL_SURFACE.json"
  fi

  # ══════════════════════════════════════════════════════════════════════════
  # PHASE 2: Consumer Impact Scanning (parallel)
  # ══════════════════════════════════════════════════════════════════════════
  # For each consumer repo:
  #   Step 2a: Clone the repo (sequential, to avoid git conflicts)
  #   Step 2b: Run grep pre-filter to identify potentially affected files
  #   Step 2c: Run ATX consumer-impact transform (parallel, up to $PARALLEL jobs)
  #
  # The pre-filter step is a performance optimization. Running ATX on a large
  # repo is expensive; grep quickly narrows down which files are relevant.

  log_info ""
  log_info "════════════════════════════════════════════════════════════════"
  log_info "  PHASE 2: Consumer Repository Impact Scanning (parallel=$PARALLEL)"
  log_info "════════════════════════════════════════════════════════════════"

  # ── Step 2a: Clone all consumer repos (parallel) ────────────────────────
  # Cloning is I/O-bound (network), so we parallelize it up to $PARALLEL jobs.
  # Each clone writes its status to a temp file to avoid race conditions on the array.
  log_info "Cloning consumer repositories (parallel=$PARALLEL)..."
  declare -a cloned_repos=()
  local clone_status_dir="${WORKSPACE}/.clone_status"
  mkdir -p "$clone_status_dir"

  clone_single_repo() {
    local repo_id="$1"
    local url
    url="$(resolve_repo_url "$repo_id")"
    local name
    name="$(repo_name_from_url "$url")"
    local repo_path="${repos_dir}/${name}"
    local status_marker="${clone_status_dir}/${name}"

    if [[ -d "$repo_path" ]]; then
      log_info "Already cloned: $name"
      echo "OK" > "$status_marker"
    else
      log_info "Cloning $url"
      if clone_repo "$url" "$repo_path"; then
        echo "OK" > "$status_marker"
      else
        log_error "Failed to clone $url"
        echo "FAILED" > "$status_marker"
        echo "${name}|CLONE_FAILED|0" >> "$status_file"
      fi
    fi
  }

  local clone_running=0
  declare -a clone_pids=()

  for repo_id in "${CONSUMER_REPOS[@]}"; do
    clone_single_repo "$repo_id" &
    clone_pids+=($!)
    clone_running=$((clone_running + 1))

    if [[ $clone_running -ge $PARALLEL ]]; then
      wait -n 2>/dev/null || true
      clone_running=$((clone_running - 1))
    fi
  done

  # Wait for all clones to finish
  for pid in "${clone_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Collect successfully cloned repos
  for repo_id in "${CONSUMER_REPOS[@]}"; do
    local url
    url="$(resolve_repo_url "$repo_id")"
    local name
    name="$(repo_name_from_url "$url")"
    if [[ -f "${clone_status_dir}/${name}" && "$(cat "${clone_status_dir}/${name}")" == "OK" ]]; then
      cloned_repos+=("$repo_id")
    fi
  done

  # Clean up temp status dir
  rm -rf "$clone_status_dir"

  # ── Step 2b: Pre-filter all cloned repos (parallel) ─────────────────────
  # Grep is CPU-bound per repo but fast; we parallelize to overlap I/O.
  log_info "Running grep pre-filter on ${#cloned_repos[@]} repos (parallel=$PARALLEL)..."
  local filter_running=0
  declare -a filter_pids=()

  for repo_id in "${cloned_repos[@]}"; do
    local url
    url="$(resolve_repo_url "$repo_id")"
    local name
    name="$(repo_name_from_url "$url")"
    local repo_path="${repos_dir}/${name}"
    local prefilter_file="${prefilter_dir}/${name}.txt"

    prefilter_repo "$repo_path" "$external_surface" "$prefilter_file" &
    filter_pids+=($!)
    filter_running=$((filter_running + 1))

    if [[ $filter_running -ge $PARALLEL ]]; then
      wait -n 2>/dev/null || true
      filter_running=$((filter_running - 1))
    fi
  done

  # Wait for all pre-filters to finish
  for pid in "${filter_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # ── Step 2b.1: Optionally skip repos with no grep matches ─────────────
  # If --skip-no-matches is set, repos where grep found nothing are excluded
  # from the expensive ATX scan. They get marked as SKIPPED in the status file.
  declare -a atx_repos=()
  if [[ "$SKIP_NO_MATCHES" == true ]]; then
    for repo_id in "${cloned_repos[@]}"; do
      local url
      url="$(resolve_repo_url "$repo_id")"
      local name
      name="$(repo_name_from_url "$url")"
      local prefilter_file="${prefilter_dir}/${name}.txt"
      local prefilter_status
      prefilter_status="$(head -1 "$prefilter_file" 2>/dev/null || echo "NO_PREFILTER")"

      if [[ "$prefilter_status" == "NO_MATCHES" ]]; then
        log_info "Skipping $name (no grep matches, --skip-no-matches)"
        echo "${name}|SKIPPED_NO_MATCHES|0" >> "$status_file"
      else
        atx_repos+=("$repo_id")
      fi
    done
    log_info "${#atx_repos[@]} repos passed pre-filter (${#cloned_repos[@]} total cloned)"
  else
    atx_repos=("${cloned_repos[@]}")
  fi

  # ── Step 2c: Run ATX analysis in parallel batches ──────────────────────
  # Worker function for a single consumer repo.
  # Each worker:
  #   1. Reads the pre-filter results to build context about which files matter
  #   2. Constructs a JSON config file with the source change plan + pre-filter hints
  #   3. Truncates context to fit ATX's 4096-char limit for additionalPlanContext
  #   4. Executes the ATX consumer-impact transform
  #   5. Writes status (SUCCESS/ATX_FAILED) to the shared status file
  run_consumer_worker() {
    local repo_id="$1"
    local url
    url="$(resolve_repo_url "$repo_id")"
    local name
    name="$(repo_name_from_url "$url")"
    local repo_path="${repos_dir}/${name}"
    local prefilter_file="${prefilter_dir}/${name}.txt"
    local worker_log="${logs_dir}/${name}.log"
    local config_file="${logs_dir}/${name}-config.json"

    # Determine pre-filter status and build context string for ATX.
    # Three possible states:
    #   NO_MATCHES   — grep ran but found nothing; ATX should look for indirect deps
    #   NO_PREFILTER — no symbols available; ATX must do a full scan
    #   (file list)  — grep found matching files; ATX should prioritize these
    local prefilter_status
    prefilter_status="$(head -1 "$prefilter_file" 2>/dev/null || echo "NO_PREFILTER")"

    local prefilter_context=""
    local match_count=0

    if [[ "$prefilter_status" == "NO_MATCHES" ]]; then
      prefilter_context="PRE-FILTER: Grep found NO direct symbol matches in this repo. Focus on indirect dependencies: REST API calls, message queue consumers, shared database access, or vendored code."
    elif [[ "$prefilter_status" == "NO_PREFILTER" ]]; then
      prefilter_context="PRE-FILTER: Not available. Perform full scan."
    else
      match_count=$(wc -l < "$prefilter_file" | xargs)
      local relative_matches
      relative_matches=$(sed "s|${repo_path}/||g" "$prefilter_file" | head -100)
      prefilter_context="PRE-FILTER: Grep found ${match_count} files with potential matches. Prioritize these files: ${relative_matches}"
    fi

    # Write config to JSON file — truncate context to fit ATX 4096 char limit.
    # The context combines: source change plan + pre-filter hints + change request.
    # Python handles the truncation logic to maximize useful information within limits.
    python3 -c "
import json, sys

source_plan = '''${source_plan}'''
prefilter = '''${prefilter_context}'''
change_req = '''${CHANGE_DESC}'''

# Build context, truncating source plan to fit within 4096 chars
header = 'SOURCE CHANGE PLAN:\n'
separator = '\n---\n'
footer = separator + prefilter + separator + 'CHANGE REQUEST: ' + change_req

# Calculate how much room we have for the source plan
overhead = len(header) + len(footer) + 50  # safety margin
max_plan = 4096 - overhead
if max_plan < 200:
    max_plan = 200

if len(source_plan) > max_plan:
    source_plan = source_plan[:max_plan] + '\n... [truncated]'

context = header + source_plan + footer

# Final safety check
if len(context) > 4096:
    context = context[:4090] + '...'

config = {'additionalPlanContext': context}
with open(sys.argv[1], 'w') as f:
    json.dump(config, f)
" "$config_file"

    echo "[INFO]  [${name}] Starting ATX analysis (${match_count} pre-filtered files)..." >> "$worker_log"

    local con_cmd=(atx custom def exec -p "$repo_path" -n "$CONSUMER_DEF")
    if [[ -n "$CONSUMER_TV" ]]; then
      con_cmd+=(--tv "$CONSUMER_TV")
    fi
    con_cmd+=(-g "file://${config_file}" -x -t)

    if "${con_cmd[@]}" >> "$worker_log" 2>&1; then
      echo "${name}|SUCCESS|${match_count}" >> "$status_file"
      echo "[INFO]  [${name}] Analysis succeeded." >> "$worker_log"
    else
      echo "${name}|ATX_FAILED|${match_count}" >> "$status_file"
      echo "[ERROR] [${name}] Analysis failed." >> "$worker_log"
    fi
  }

  # Launch workers with parallelism control.
  # We use background processes (&) and `wait -n` to maintain at most $PARALLEL
  # concurrent jobs. When the limit is reached, we wait for any one to finish
  # before launching the next.
  log_info "Launching ATX analysis for ${#atx_repos[@]} repos (max $PARALLEL parallel)..."

  local running=0
  declare -a pids=()

  for repo_id in "${atx_repos[@]}"; do
    local name
    name="$(repo_name_from_url "$(resolve_repo_url "$repo_id")")"
    log_info "Launching worker for: $name"

    run_consumer_worker "$repo_id" &
    pids+=($!)
    running=$((running + 1))

    # If we've hit the parallel limit, wait for one to finish
    if [[ $running -ge $PARALLEL ]]; then
      wait -n 2>/dev/null || true
      running=$((running - 1))
    fi
  done

  # Wait for all remaining workers
  log_info "Waiting for all workers to complete..."
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # ── Read results from status file ──────────────────────────────────────
  # Parse the status file to tally successes and failures.
  # Each line has format: "repo_name|STATUS|match_count"
  declare -a results=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && results+=("$line")
  done < "$status_file"

  local clone_fail=0
  local atx_success=0
  local atx_fail=0
  local atx_skipped=0

  for entry in "${results[@]}"; do
    local r_status="${entry#*|}"
    r_status="${r_status%%|*}"
    case "$r_status" in
      CLONE_FAILED)        clone_fail=$((clone_fail + 1)) ;;
      SUCCESS)             atx_success=$((atx_success + 1)) ;;
      ATX_FAILED)          atx_fail=$((atx_fail + 1)) ;;
      SKIPPED_NO_MATCHES)  atx_skipped=$((atx_skipped + 1)) ;;
    esac
  done

  # ── Move reports to results directory ────────────────────────────────────
  # ATX writes output files directly into the cloned repo directories.
  # We move them to a clean results/ tree for easier consumption.
  log_info "Moving reports to ${results_dir}/ ..."

  # Move source reports
  local source_results_dir="${results_dir}/${source_name}"
  mkdir -p "$source_results_dir"
  for f in SOURCE_CHANGE_PLAN.md EXTERNAL_SURFACE.json; do
    if [[ -f "${source_path}/${f}" ]]; then
      mv "${source_path}/${f}" "${source_results_dir}/${f}"
    fi
  done

  # Move consumer reports
  for entry in "${results[@]}"; do
    local r_name="${entry%%|*}"
    local r_rest="${entry#*|}"
    local r_status="${r_rest%%|*}"
    if [[ "$r_status" == "SUCCESS" ]]; then
      local consumer_results_dir="${results_dir}/${r_name}"
      mkdir -p "$consumer_results_dir"
      if [[ -f "${repos_dir}/${r_name}/IMPACT_REPORT.md" ]]; then
        mv "${repos_dir}/${r_name}/IMPACT_REPORT.md" "${consumer_results_dir}/IMPACT_REPORT.md"
      fi
    fi
  done

  # ── Generate consolidated report ─────────────────────────────────────────
  # Combines the source change plan and all consumer impact reports into a
  # single markdown document for easy review. Includes metadata (date, counts)
  # and per-repo status with full report content or error messages.
  local consolidated="${results_dir}/CONSOLIDATED_IMPACT_REPORT.md"
  log_info "Generating consolidated report: $consolidated"

  {
    echo "# Consolidated Change Impact Analysis Report"
    echo ""
    echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**Source Repository:** $source_name"
    echo "**Change Request:** $(echo "$CHANGE_DESC" | head -1)"
    echo "**Consumer Repos Scanned:** ${#CONSUMER_REPOS[@]}"
    echo "**Succeeded:** $atx_success | **Failed:** $atx_fail | **Skipped:** $atx_skipped | **Clone Failed:** $clone_fail"
    echo ""
    echo "---"
    echo ""

    # Include source change plan if available
    if [[ -f "${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md" ]]; then
      echo "## Source Change Plan"
      echo ""
      cat "${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md"
      echo ""
      echo "---"
      echo ""
    fi

    # Include each consumer impact report
    echo "## Consumer Repository Impact Reports"
    echo ""

    for entry in "${results[@]}"; do
      local r_name="${entry%%|*}"
      local r_rest="${entry#*|}"
      local r_status="${r_rest%%|*}"
      local r_matches="${r_rest#*|}"

      echo "### $r_name"
      echo ""

      case "$r_status" in
        SUCCESS)
          if [[ -f "${results_dir}/${r_name}/IMPACT_REPORT.md" ]]; then
            cat "${results_dir}/${r_name}/IMPACT_REPORT.md"
          else
            echo "*Analysis succeeded but no IMPACT_REPORT.md was generated.*"
          fi
          ;;
        CLONE_FAILED)
          echo "❌ **Clone failed** — repository could not be cloned."
          ;;
        ATX_FAILED)
          echo "❌ **Analysis failed** (${r_matches} pre-filtered files). Check logs: ${logs_dir}/${r_name}.log"
          ;;
        SKIPPED_NO_MATCHES)
          echo "⏭️ **Skipped** — grep pre-filter found no symbol matches. Likely not impacted."
          ;;
      esac

      echo ""
      echo "---"
      echo ""
    done
  } > "$consolidated"

  log_info "Consolidated report saved to: $consolidated"

  # ── Summary ────────────────────────────────────────────────────────────────
  # Print a human-friendly summary to stdout showing overall results,
  # per-repo status with emoji indicators, and paths to all output files.
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Change Impact Analysis — Final Summary"
  echo "════════════════════════════════════════════════════════════════"
  echo "Change request      : $(echo "$CHANGE_DESC" | head -1)"
  echo "Source repository    : $source_name"
  echo "Consumer repos       : ${#CONSUMER_REPOS[@]}"
  echo "Clone failures       : $clone_fail"
  echo "ATX succeeded        : $atx_success"
  echo "ATX failed           : $atx_fail"
  echo "ATX skipped          : $atx_skipped"
  echo "────────────────────────────────────────────────────────────────"

  for entry in "${results[@]}"; do
    local r_name="${entry%%|*}"
    local r_rest="${entry#*|}"
    local r_status="${r_rest%%|*}"
    local r_matches="${r_rest#*|}"
    case "$r_status" in
      SUCCESS)             echo "  ✅  $r_name  (${r_matches} pre-filtered files)" ;;
      CLONE_FAILED)        echo "  ❌  $r_name  (clone failed)" ;;
      ATX_FAILED)          echo "  ❌  $r_name  (analysis failed, ${r_matches} pre-filtered files)" ;;
      SKIPPED_NO_MATCHES)  echo "  ⏭️   $r_name  (skipped — no grep matches)" ;;
    esac
  done

  echo ""
  echo "Reports saved to:"
  echo "  Consolidated: ${results_dir}/CONSOLIDATED_IMPACT_REPORT.md"
  echo "  Source:       ${results_dir}/${source_name}/SOURCE_CHANGE_PLAN.md"
  echo "  Surface:      ${results_dir}/${source_name}/EXTERNAL_SURFACE.json"
  for entry in "${results[@]}"; do
    local r_name="${entry%%|*}"
    local r_rest="${entry#*|}"
    local r_status="${r_rest%%|*}"
    if [[ "$r_status" == "SUCCESS" ]]; then
      echo "  Consumer: ${results_dir}/${r_name}/IMPACT_REPORT.md"
    fi
  done
  echo "  Logs:     ${logs_dir}/"
  echo "════════════════════════════════════════════════════════════════"

  # Exit with code 2 if any repos failed (partial success).
  # This allows CI pipelines to distinguish "all good" from "some problems".
  if [[ $clone_fail -gt 0 || $atx_fail -gt 0 ]]; then
    exit 2
  fi
}

# Entry point — pass all script arguments to main()
main "$@"
