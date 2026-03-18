#!/usr/bin/env bash
set -euo pipefail

VENDOR_DIR="${EFOOTPRINT_VENDOR_DIR:-.vendor/e-footprint}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

if [ ! -f ".env.local" ] && [ ! -f ".env" ]; then
  cat > .env.local <<'EOF'
# Local development environment
# Keep DJANGO_DOCKER unset to use SQLite defaults from settings.py
EOF
fi

if [ ! -d "$VENDOR_DIR" ]; then
  echo "Error: EFOOTPRINT_VENDOR_DIR '$VENDOR_DIR' does not exist."
  echo "Point EFOOTPRINT_VENDOR_DIR to an existing local e-footprint checkout."
  exit 1
fi

export PYTHONPATH="$PWD/$VENDOR_DIR:${PYTHONPATH:-}"

if command -v uv >/dev/null 2>&1; then
  PY_CMD=(uv run python)
else
  PY_CMD=(poetry run python)
fi

"${PY_CMD[@]}" manage.py migrate
"${PY_CMD[@]}" manage.py createcachetable || true
"${PY_CMD[@]}" manage.py runserver "$HOST:$PORT"
