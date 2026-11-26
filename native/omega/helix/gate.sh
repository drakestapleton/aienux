#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Pure-Omega AienOS Helix gate (ZERO C, ZERO Python, ZERO nvidia.ko, ZERO host firmware touches).
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OM_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT=${1:-$HERE/build}
OMC=${OMC:-$HOME/canon/omega-mv/seed/out/omc}
OLLM=${OLLM:-$HOME/.local/opt/omega-helix/bin/ollm-gb10}
CKPT=${CKPT:-$HOME/work/helix-35b-overnight-20261125/bundles/seed_d2048_8x4.ck}
MERGES=${MERGES:-$HOME/work/helix-35b-overnight-20261125/data/merges4096.bin}
mkdir -p "$OUT"

echo "=== 1. Build pure-Omega aienos-helix runtime (allen/base + allen/runtime + aienos_helix) ==="
UNIT="$OUT/aienos-helix.om"
cat "$OM_ROOT/allen/base.om" "$OM_ROOT/allen/runtime.om" "$HERE/aienos_helix.om" > "$UNIT"
dup=$(grep -E "^(fn|global|const|text|struct) " "$UNIT" | awk "{print \$2}" | sort | uniq -d)
[ -z "$dup" ] || { echo "duplicate symbols: $dup" >&2; exit 65; }
"$OMC" < "$UNIT" > "$OUT/aienos-helix.tmp"
chmod +x "$OUT/aienos-helix.tmp"
mv -f "$OUT/aienos-helix.tmp" "$OUT/aienos-helix"
printf "built %s (%s bytes, sha256=%s)\n" \
  "$OUT/aienos-helix" \
  "$(wc -c < "$OUT/aienos-helix" | tr -d " ")" \
  "$(sha256sum "$OUT/aienos-helix" | awk "{print \$1}")"

echo "=== 2. Negative control: empty prompt MUST be refused by Allen before touching GPU ==="
set +e
neg_out=$("$OUT/aienos-helix" "$OLLM" "$CKPT" "$MERGES" 8 "")
neg_rc=$?
set -e
printf "%s (rc=%d)\n" "$neg_out" "$neg_rc"
[ "$neg_rc" -eq 2 ] || { echo "FAIL: expected rc=2 for empty prompt" >&2; exit 1; }
printf "%s" "$neg_out" | grep -q "AIENOS_HELIX_REFUSED reason=allen_admission"

echo "=== 3. Positive live turn on GB20B /dev/aien-gpu (D=2048 8x4 read-only, ZERO nvidia.ko) ==="
if [ -r /dev/aien-gpu ] && [ -w /dev/aien-gpu ] && [ -x "$OLLM" ] && [ -r "$CKPT" ] && [ -r "$MERGES" ]; then
  "$OUT/aienos-helix" "$OLLM" "$CKPT" "$MERGES" 24 "fn solve a ulong to ulong"
  live_status=PASS
else
  echo "SKIP_LIVE: missing /dev/aien-gpu or ollm-gb10/ckpt"
  live_status=SKIPPED
fi

echo "=== 4. Build & QEMU-boot pure-Omega AArch64 EFI image (build/ only, ZERO host firmware touches) ==="
sh "$HERE/build-a64efi-helix.sh" "$OUT"
efi_status=BUILT_ONLY
CODE_FD="${AAVMF_CODE:-/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd}"
VARS_FD="${AAVMF_VARS:-/usr/share/AAVMF/AAVMF_VARS.fd}"
if command -v qemu-system-aarch64 >/dev/null 2>&1 && [ -r "$CODE_FD" ] && [ -r "$VARS_FD" ]; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir -p "$work/esp/EFI/BOOT" "$work/esp/OLLM"
  cp "$OUT/AIENOS-HELIX-AA64.EFI" "$work/esp/EFI/BOOT/BOOTAA64.EFI"
  : > "$work/esp/OLLM/REBOOT.TXT"
  cp "$VARS_FD" "$work/vars.fd"
  set +e
  timeout 60 qemu-system-aarch64 \
    -M virt,gic-version=3 -accel tcg,thread=single -cpu max -smp 2 -m 512 \
    -drive if=pflash,format=raw,readonly=on,file="$CODE_FD" \
    -drive if=pflash,format=raw,file="$work/vars.fd" \
    -drive if=none,id=esp,format=raw,file=fat:rw:"$work/esp" \
    -device virtio-blk-pci,drive=esp \
    -display none -nic none \
    -serial file:"$work/serial.log" -no-reboot
  qrc=$?
  set -e
  tr -d "\r" < "$work/serial.log" > "$OUT/qemu-a64efi-serial.log"
  grep "AIENOS_EFI_HELIX_AA64:" "$OUT/qemu-a64efi-serial.log"
  grep -q "AIENOS_EFI_HELIX_AA64: PASS gpu_units=ident+gmmu+gb20b_policy allen_seq=1 allen_hist=2" "$OUT/qemu-a64efi-serial.log"
  echo "qemu_a64efi_rc=$qrc"
  rm -rf "$work"
  trap - EXIT
  efi_status=QEMU_PASS
fi

echo "AIENOS_OMEGA_HELIX_GATE: PASS live_gpu=$live_status a64efi=$efi_status"
