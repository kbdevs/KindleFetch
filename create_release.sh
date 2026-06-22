#!/usr/bin/env bash
set -euo pipefail

rm -f kindlefetch.zip
rm -f kindlefetch/bin/kindlefetch_config
rm -f kindlefetch/bin/zlib_cookies.txt
rm -f kindlefetch/bin/.version

VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
echo "$VERSION" > "kindlefetch/bin/.version"

find kindlefetch -name ".DS_Store" -delete

zip -r kindlefetch.zip kindlefetch
