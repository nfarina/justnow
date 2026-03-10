#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRANGLER_CONFIG_PATH="${REPO_ROOT}/wrangler.jsonc"
SITE_DIR="${REPO_ROOT}/site"
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT_NAME:-}"
BRANCH="${CLOUDFLARE_PAGES_BRANCH:-main}"
COMMIT_HASH="${CLOUDFLARE_PAGES_COMMIT_HASH:-}"
COMMIT_MESSAGE="${CLOUDFLARE_PAGES_COMMIT_MESSAGE:-}"

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/deploy-public-site.sh [options]

Options:
  --project-name <name>    Cloudflare Pages project name (defaults to wrangler.jsonc name)
  --branch <name>          Pages branch/environment name (default: main)
  --commit-hash <sha>      Commit SHA attached to the deployment
  --commit-message <msg>   Commit message attached to the deployment
EOF
}

resolve_project_name() {
  if [ -n "${PROJECT_NAME}" ]; then
    return
  fi

  if [ ! -f "${WRANGLER_CONFIG_PATH}" ]; then
    echo "Could not find wrangler config at ${WRANGLER_CONFIG_PATH}" >&2
    exit 1
  fi

  PROJECT_NAME="$(
    python3 - "${WRANGLER_CONFIG_PATH}" <<'PY'
import json
import pathlib
import sys

config_path = pathlib.Path(sys.argv[1])
payload = json.loads(config_path.read_text(encoding="utf-8"))
name = payload.get("name", "")
if not name:
    raise SystemExit(1)
print(name)
PY
  )"

  if [ -z "${PROJECT_NAME}" ]; then
    echo "Could not resolve Cloudflare Pages project name from ${WRANGLER_CONFIG_PATH}" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      [[ -n "${2:-}" ]] || { echo "--project-name requires a value"; usage; exit 1; }
      PROJECT_NAME="$2"
      shift 2
      ;;
    --branch)
      [[ -n "${2:-}" ]] || { echo "--branch requires a value"; usage; exit 1; }
      BRANCH="$2"
      shift 2
      ;;
    --commit-hash)
      [[ -n "${2:-}" ]] || { echo "--commit-hash requires a value"; usage; exit 1; }
      COMMIT_HASH="$2"
      shift 2
      ;;
    --commit-message)
      [[ -n "${2:-}" ]] || { echo "--commit-message requires a value"; usage; exit 1; }
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

resolve_project_name

if [ ! -d "${SITE_DIR}" ]; then
  echo "Could not find site directory at ${SITE_DIR}" >&2
  exit 1
fi

if ! npx wrangler whoami >/dev/null 2>&1; then
  echo "Wrangler is not authenticated. Run: npx wrangler login" >&2
  exit 1
fi

DEPLOY_CMD=(
  npx wrangler pages deploy "${SITE_DIR}"
  --project-name "${PROJECT_NAME}"
  --branch "${BRANCH}"
  --commit-dirty=true
)

if [ -n "${COMMIT_HASH}" ]; then
  DEPLOY_CMD+=(--commit-hash "${COMMIT_HASH}")
fi

if [ -n "${COMMIT_MESSAGE}" ]; then
  DEPLOY_CMD+=(--commit-message "${COMMIT_MESSAGE}")
fi

"${DEPLOY_CMD[@]}"
