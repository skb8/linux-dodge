#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export LLVM="${LLVM:--18}"
profile="${DISPLAY_PROFILE:-firmware}"
case "$profile" in firmware|native) ;; *) echo "Unknown display profile: $profile" >&2; exit 2;; esac
mkdir -p build-logs dist
export KBUILD_BUILD_TIMESTAMP="$(git show -s --format=%cD HEAD)"
make O=out defconfig sm8750.config 2>&1 | tee build-logs/base-config.log
scripts/kconfig/merge_config.sh -m -O out out/.config arch/arm64/configs/dodge-mu.config \
  2>&1 | tee build-logs/merge-config.log
scripts/config --file out/.config --set-str LOCALVERSION "-dodge-mu-$profile" \
  --set-str SYSTEM_TRUSTED_KEYS '' --set-str SYSTEM_REVOCATION_KEYS ''
if [[ "$profile" == firmware ]]; then
  # Keep the Mu GOP framebuffer; do not attempt an unvalidated DSI takeover.
  scripts/config --file out/.config -d DRM_MSM -d DRM_PANEL_ONEPLUS_DODGE
else
  scripts/config --file out/.config -e DRM_MSM -e DRM_PANEL_ONEPLUS_DODGE
fi
make O=out olddefconfig 2>&1 | tee build-logs/olddefconfig.log
# Fail if Kconfig silently dropped anything essential for this payload.
required=(EFI EFI_STUB EFI_ARMSTUB_DTB_LOADER BLK_DEV_INITRD DEVTMPFS EXT4_FS
  DRM DRM_SIMPLEDRM SYSFB_SIMPLEFB INPUT_EVDEV TOUCHSCREEN_SYNA_TCM2
  SPI_QCOM_GENI SCSI_UFS_QCOM PHY_QCOM_QMP_UFS USB_DWC3 USB_DWC3_QCOM USB_G_NCM)
if [[ "$profile" == native ]]; then required+=(DRM_MSM DRM_PANEL_ONEPLUS_DODGE); fi
for symbol in "${required[@]}"; do
  if ! grep -qx "CONFIG_${symbol}=y" out/.config; then
    echo "Required built-in option missing: CONFIG_$symbol" >&2; exit 1
  fi
done
grep -qx '# CONFIG_QCOM_Q6V5_PAS is not set' out/.config
if [[ "$profile" == firmware ]]; then grep -qx '# CONFIG_DRM_MSM is not set' out/.config; fi
make -j"${JOBS:-$(nproc)}" O=out Image Image.gz modules qcom/sm8750-oneplus-dodge.dtb \
  2>&1 | tee build-logs/build.log
release="$(make -s O=out kernelrelease)"
make O=out INSTALL_MOD_PATH="$PWD/out/modules-root" INSTALL_MOD_STRIP=1 modules_install \
  2>&1 | tee build-logs/modules-install.log
# Do not ship symlinks to the runner's build directory.
rm -f "out/modules-root/lib/modules/$release/build" "out/modules-root/lib/modules/$release/source"
tar -C out/modules-root -czf dist/modules.tar.gz lib
cp out/arch/arm64/boot/Image dist/Image
cp out/arch/arm64/boot/Image dist/linux.efi
cp out/arch/arm64/boot/Image.gz dist/Image.gz
cp out/arch/arm64/boot/dts/qcom/sm8750-oneplus-dodge.dtb dist/
cp out/.config dist/kernel.config
cp out/System.map dist/
cp Documentation/arm64/oneplus13-mu.rst dist/README.rst
printf '%s\n' "$release" > dist/kernelrelease.txt
{
  printf 'source_commit=%s\ndisplay_profile=%s\nkernelrelease=%s\n' "$(git rev-parse HEAD)" "$profile" "$release"
  clang-18 --version
  ld.lld-18 --version
} > dist/build-info.txt
python3 - <<'PY'
from pathlib import Path
import struct
p = Path('dist/linux.efi').read_bytes()
assert p[:2] == b'MZ', 'Missing EFI DOS header'
pe = struct.unpack_from('<I', p, 0x3c)[0]
assert p[pe:pe+4] == b'PE\0\0', 'Missing PE signature'
assert struct.unpack_from('<H', p, pe+4)[0] == 0xaa64, 'Not an ARM64 EFI image'
dtb = Path('dist/sm8750-oneplus-dodge.dtb').read_bytes()
assert dtb[:4] == bytes.fromhex('d00dfeed'), 'Invalid DTB magic'
print('ARM64 EFI image and DTB headers verified')
PY
(cd dist && sha256sum Image linux.efi Image.gz *.dtb modules.tar.gz kernel.config System.map \
  kernelrelease.txt build-info.txt README.rst > SHA256SUMS)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### OnePlus 13: %s\n\nKernel: `%s`\n\n' "$profile" "$release"
    printf 'EFI payload, DTB, modules, config and checksums built. Hardware boot remains untested.\n'
    printf 'Debian/Arch rootfs and its initramfs must be prepared separately.\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi
