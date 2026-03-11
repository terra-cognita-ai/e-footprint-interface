#!/usr/bin/env bash
set -euo pipefail

BRANCH="${EFOOTPRINT_BRANCH:-ecologits-generic}"
REPO_URL="${EFOOTPRINT_REPO_URL:-https://github.com/terra-cognita-ai/e-footprint.git}"
VENDOR_DIR="${EFOOTPRINT_VENDOR_DIR:-.vendor/e-footprint}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

if [ ! -f ".env.local" ] && [ ! -f ".env" ]; then
  cat > .env.local <<'EOF'
# Local development environment
# Keep DJANGO_DOCKER unset to use SQLite defaults from settings.py
EOF
fi

mkdir -p "$(dirname "$VENDOR_DIR")"

if [ ! -d "$VENDOR_DIR/.git" ]; then
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$VENDOR_DIR"
else
  git -C "$VENDOR_DIR" fetch origin "$BRANCH"
  git -C "$VENDOR_DIR" checkout "$BRANCH"
  git -C "$VENDOR_DIR" pull --ff-only
fi

export PYTHONPATH="$PWD/$VENDOR_DIR:${PYTHONPATH:-}"

poetry run python manage.py migrate
poetry run python manage.py createcachetable || true
poetry run python manage.py runserver "$HOST:$PORT"
