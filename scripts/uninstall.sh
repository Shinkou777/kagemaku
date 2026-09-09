#!/bin/bash
# 卸载。加 --purge 连皮肤和遮挡条数据一起删
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
sed "s|__REPO__|$REPO|g" "$REPO/scripts/kagemaku" > /tmp/kagemaku-cli
chmod +x /tmp/kagemaku-cli
/tmp/kagemaku-cli uninstall "${1:-}"
