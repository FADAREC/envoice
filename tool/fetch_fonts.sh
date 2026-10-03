#!/usr/bin/env bash
set -euo pipefail
mkdir -p assets/fonts
curl -fsSL -o assets/fonts/NotoSans-Regular.ttf \
  "https://github.com/google/fonts/raw/main/ofl/notosans/NotoSans%5Bwdth%2Cwght%5D.ttf"
cp assets/fonts/NotoSans-Regular.ttf assets/fonts/NotoSans-Bold.ttf
echo "Fonts ready under assets/fonts/"
ls -la assets/fonts/
