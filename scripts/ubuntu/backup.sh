#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${1:-/var/backups/zerotier-gateway}"
mkdir -p "$BACKUP_DIR"
printf 'Backup directory: %s\n' "$BACKUP_DIR"
