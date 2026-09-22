#!/usr/bin/env bash
set -euo pipefail

# Ejecutar en la VM desde /opt/garibaldi. No restaura ni elimina datos.
project_dir="${PROJECT_DIR:-/opt/garibaldi}"
backup_dir="${BACKUP_DIR:-/opt/garibaldi/backups/postgres}"
keep_days="${BACKUP_KEEP_DAYS:-14}"

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="$backup_dir/balam-$timestamp.sql.gz"

cd "$project_dir"
docker compose -f docker-compose.yml -f docker-compose.oracle.yml exec -T postgres \
  pg_dump -U balam -d balam | gzip -9 > "$target"
chmod 600 "$target"
find "$backup_dir" -type f -name 'balam-*.sql.gz' -mtime "+$keep_days" -delete
echo "Backup creado: $target"
