#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Build pure-Omega AArch64 bare-metal EFI image (AIENOS-HELIX-AA64.EFI) strictly inside build/.
# For QEMU testing only; never touches host firmware or system partitions.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OM_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT=${1:-$HERE/build}
OMC=${OMC:-$HOME/canon/omega-mv/seed/out/omc}
EFIRT=${EFIRT:-$HOME/canon/omega-mv/seed/a64efi/efirt.om}
mkdir -p "$OUT"

UNIT="$OUT/aienos-helix-a64efi.om"
{
  printf "target a64efi\n"
  cat "$EFIRT" \
      "$OM_ROOT/allen/base.om" \
      "$OM_ROOT/allen/runtime.om" \
      "$OM_ROOT/gpu/units/ident.om" \
      "$OM_ROOT/gpu/units/gmmu.om" \
      "$OM_ROOT/gpu/units/gb20b_policy.om" \
      "$HERE/efi_helix.om"
} > "$UNIT"

dup=$(grep -E "^(fn|global|const|text|struct) " "$UNIT" | awk "{print \$2}" | sort | uniq -d)
[ -z "$dup" ] || { echo "duplicate symbols in a64efi unit: $dup" >&2; exit 65; }

"$OMC" < "$UNIT" > "$OUT/AIENOS-HELIX-AA64.EFI.tmp"
[ -s "$OUT/AIENOS-HELIX-AA64.EFI.tmp" ]
[ "$(head -c 2 "$OUT/AIENOS-HELIX-AA64.EFI.tmp")" = "MZ" ] || { echo "not a PE32+ EFI image" >&2; exit 65; }
mv -f "$OUT/AIENOS-HELIX-AA64.EFI.tmp" "$OUT/AIENOS-HELIX-AA64.EFI"
printf "built %s (%s bytes, sha256=%s)\n" \
  "$OUT/AIENOS-HELIX-AA64.EFI" \
  "$(wc -c < "$OUT/AIENOS-HELIX-AA64.EFI" | tr -d " ")" \
  "$(sha256sum "$OUT/AIENOS-HELIX-AA64.EFI" | awk "{print \$1}")"
file "$OUT/AIENOS-HELIX-AA64.EFI"
