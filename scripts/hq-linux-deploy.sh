#!/usr/bin/env bash
# HQ Linux auto-deploy (GitHub Actions: hq-linux-deploy.yml, runner label linux+hq).
set -euo pipefail
REPO="${HQ_KCW_DOCS_DIR:-$HOME/projects/kcw-docs}"
cd "$REPO"
git fetch origin
git reset --hard origin/main
echo "kcw-docs deployed at $(git rev-parse --short HEAD) ($(git log -1 --format='%s'))"
