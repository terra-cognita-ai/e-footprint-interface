#!/usr/bin/env bash
set -euo pipefail

VENDOR_DIR="${EFOOTPRINT_VENDOR_DIR:-.vendor/e-footprint}"
EFOOTPRINT_REPO_URL="${EFOOTPRINT_REPO_URL:-https://github.com/terra-cognita-ai/e-footprint.git}"
EFOOTPRINT_BRANCH="${EFOOTPRINT_BRANCH:-ecologits-generic}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
Usage: scripts/run_with_efootprint_branch.sh

Environment variables:
  EFOOTPRINT_VENDOR_DIR  Local checkout path (default: .vendor/e-footprint)
  EFOOTPRINT_REPO_URL    e-footprint git URL
  EFOOTPRINT_BRANCH      e-footprint branch to use (default: ecologits-generic)
  HOST                   Django host (default: 127.0.0.1)
  PORT                   Django port (default: 8000)
EOF
  exit 0
fi

ensure_vendor_checkout() {
  mkdir -p "$(dirname "$VENDOR_DIR")"

  if [ ! -d "$VENDOR_DIR/.git" ]; then
    if [ -e "$VENDOR_DIR" ] && [ ! -d "$VENDOR_DIR/.git" ]; then
      echo "Error: '$VENDOR_DIR' exists but is not a git checkout."
      echo "Remove it or point EFOOTPRINT_VENDOR_DIR to a valid e-footprint git repository."
      exit 1
    fi

    echo "Cloning e-footprint into $VENDOR_DIR (branch: $EFOOTPRINT_BRANCH)"
    git clone --branch "$EFOOTPRINT_BRANCH" --single-branch "$EFOOTPRINT_REPO_URL" "$VENDOR_DIR"
    return
  fi

  if ! git -C "$VENDOR_DIR" remote get-url origin >/dev/null 2>&1; then
    echo "Error: '$VENDOR_DIR' is missing a git origin remote."
    exit 1
  fi

  CURRENT_BRANCH="$(git -C "$VENDOR_DIR" branch --show-current 2>/dev/null || true)"
  if [ -z "$CURRENT_BRANCH" ]; then
    if [ -n "$(git -C "$VENDOR_DIR" status --porcelain 2>/dev/null || true)" ]; then
      echo "Error: '$VENDOR_DIR' does not have a valid checked-out branch and contains local changes."
      echo "Commit/stash changes, then rerun to checkout '$EFOOTPRINT_BRANCH'."
      exit 1
    fi
    echo "Checking out branch $EFOOTPRINT_BRANCH in $VENDOR_DIR"
    git -C "$VENDOR_DIR" fetch origin "$EFOOTPRINT_BRANCH"
    git -C "$VENDOR_DIR" checkout -B "$EFOOTPRINT_BRANCH" "origin/$EFOOTPRINT_BRANCH"
    CURRENT_BRANCH="$EFOOTPRINT_BRANCH"
  fi
  if [ "$CURRENT_BRANCH" != "$EFOOTPRINT_BRANCH" ]; then
    if [ -n "$(git -C "$VENDOR_DIR" status --porcelain)" ]; then
      echo "Error: '$VENDOR_DIR' has uncommitted changes and is on '$CURRENT_BRANCH'."
      echo "Commit/stash changes before switching to '$EFOOTPRINT_BRANCH', or set EFOOTPRINT_BRANCH to '$CURRENT_BRANCH'."
      exit 1
    fi
    echo "Switching $VENDOR_DIR to branch $EFOOTPRINT_BRANCH"
    git -C "$VENDOR_DIR" fetch origin "$EFOOTPRINT_BRANCH"
    git -C "$VENDOR_DIR" checkout "$EFOOTPRINT_BRANCH"
    git -C "$VENDOR_DIR" pull --ff-only origin "$EFOOTPRINT_BRANCH"
  else
    echo "Updating $VENDOR_DIR on $EFOOTPRINT_BRANCH"
    git -C "$VENDOR_DIR" pull --ff-only origin "$EFOOTPRINT_BRANCH" || true
  fi
}

ensure_vendor_pyproject_build_backend() {
  local vendor_pyproject
  vendor_pyproject="$VENDOR_DIR/pyproject.toml"

  if [ ! -f "$vendor_pyproject" ]; then
    echo "Error: expected '$vendor_pyproject' to exist."
    exit 1
  fi

  if grep -q '^\[build-system\]' "$vendor_pyproject"; then
    return
  fi

  echo "Injecting [build-system] into $vendor_pyproject for reliable PEP517 builds"
  local tmp_file
  tmp_file="$(mktemp)"
  cat > "$tmp_file" <<'EOF'
[build-system]
requires = ["poetry-core>=1.0.0"]
build-backend = "poetry.core.masonry.api"

EOF
  cat "$vendor_pyproject" >> "$tmp_file"
  mv "$tmp_file" "$vendor_pyproject"
}

if [ ! -f ".env.local" ] && [ ! -f ".env" ]; then
  cat > .env.local <<'EOF'
# Local development environment
# Keep DJANGO_DOCKER unset to use SQLite defaults from settings.py
EOF
fi

ensure_vendor_checkout
ensure_vendor_pyproject_build_backend

export PYTHONPATH="$PWD/$VENDOR_DIR:${PYTHONPATH:-}"

if command -v uv >/dev/null 2>&1; then
  PY_CMD=(uv run python)
else
  PY_CMD=(poetry run python)
fi

"${PY_CMD[@]}" manage.py migrate
"${PY_CMD[@]}" manage.py createcachetable || true
"${PY_CMD[@]}" manage.py runserver "$HOST:$PORT"
