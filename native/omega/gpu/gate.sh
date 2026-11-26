#!/bin/sh
# SPDX-License-Identifier: MIT OR GPL-2.0-only
# Pure-Omega AienOS GB20B GPU driver gate (ZERO C, ZERO Python, ZERO UEFI touches).
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/build}
OMC_K=${OMC_K:-$HOME/workspace/review-37b16a71/build/omc}
OMC_U=${OMC_U:-$HOME/canon/omega-mv/seed/out/omc}
[ -x "$OMC_K" ] || OMC_K="$OMC_U"
mkdir -p "$OUT"

echo "=== 1. Build pure-Omega kcheck + compile & verify all 16 kernel-ready GB20B .om units ==="
"$OMC_K" < "$HERE/kcheck.om" > "$OUT/kcheck.tmp"
chmod +x "$OUT/kcheck.tmp"
mv -f "$OUT/kcheck.tmp" "$OUT/kcheck"

count=0
for u in ident boot seq seal mqput mqget abi gmmu memchk rpdes rm rmchan rmctl rmchk rmarg gb20b_policy; do
  "$OMC_K" < "$HERE/units/$u.om" > "$OUT/$u.bin.tmp"
  "$OUT/kcheck" < "$OUT/$u.bin.tmp" > "$OUT/$u.kcheck"
  printf "%s: %s\n" "$u" "$(cat "$OUT/$u.kcheck")"
  mv -f "$OUT/$u.bin.tmp" "$OUT/$u.bin"
  count=$((count + 1))
done

echo "=== 2. Build & run pure-Omega GB20B unit self-test (positive + negative controls) ==="
cat "$HERE/units/ident.om" "$HERE/units/gmmu.om" "$HERE/units/gb20b_policy.om" "$HERE/gpu_selftest.om" > "$OUT/gpu_selftest.om"
"$OMC_U" < "$OUT/gpu_selftest.om" > "$OUT/gpu_selftest.tmp"
chmod +x "$OUT/gpu_selftest.tmp"
mv -f "$OUT/gpu_selftest.tmp" "$OUT/gpu_selftest"
"$OUT/gpu_selftest"

echo "=== 3. Build pure-Omega M16 hardware gate (aien_m16.om) ==="
"$OMC_U" < "$HERE/aien_m16.om" > "$OUT/aien-m16-om.tmp"
chmod +x "$OUT/aien-m16-om.tmp"
mv -f "$OUT/aien-m16-om.tmp" "$OUT/aien-m16-om"
if [ -r /dev/aien-gpu ] && [ -w /dev/aien-gpu ]; then
  "$OUT/aien-m16-om"
  echo "AIENOS_OMEGA_GPU_GATE: PASS units=$count live_m16=PASS"
else
  echo "AIENOS_OMEGA_GPU_GATE: PASS units=$count live_m16=SKIPPED_NO_DEV"
fi
