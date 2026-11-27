#!/bin/zsh
set -euo pipefail

HERE="${0:A:h}"
ROOT="${KRYPTON_ROOT:-$(brew --prefix krypton)/libexec}"
KCC="$ROOT/bootstrap/kcc_driver_macos_aarch64"
SRC="$HERE/devsweep.ks"
HELPER="$HERE/scripts/build-objk-app.ks"
OUT="$HERE/dist/DevSweep.app"

if [[ ! -x "$KCC" ]]; then
  print -u2 "build: no driver at $KCC (set KRYPTON_ROOT)"
  exit 1
fi

"$KCC" --version
"$KCC" -r "$HELPER" "$SRC" DevSweep \
  --out "$OUT" --id dev.t3m3d.devsweep --version 0.1.0 --compiler "$KCC"

if [[ -n "${DEV_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --sign "$DEV_IDENTITY" --identifier dev.t3m3d.devsweep "$OUT"
fi

plutil -lint "$OUT/Contents/Info.plist"
codesign --verify --deep --strict "$OUT"
print "built $OUT"
