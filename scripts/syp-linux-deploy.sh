#!/usr/bin/env bash
# SYP Linux auto-deploy (GitHub Actions: syp-linux-deploy.yml, runner label linux+syp).
set -euo pipefail
REPO="${SYP_KCW_DOCS_DIR:-$HOME/projects/kcw-docs}"
cd "$REPO"
git fetch origin
git reset --hard origin/main
echo "kcw-docs deployed at $(git rev-parse --short HEAD) ($(git log -1 --format='%s'))"
