#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# SukiSU-Nova build script for Xiaomi Mi 9T / Redmi K20 (davinci)
# Used by both GitHub Actions and local builds.
#
# Environment variables:
#   CLANG_DIR   Path to an AOSP clang prebuilt (required)
#   OUT         Output directory (default: ./out)
#   KSU         true/false  Integrate SukiSU-Nova (default: true)
#   KSU_REF     SukiSU-Nova branch/tag/commit (default: builtin)
#   SUSFS       true/false  Use SUSFS inline hook; false = KSU manual hook (default: true)
#   JOBS        Parallel jobs (default: nproc)
#   USE_CCACHE  true/false (default: true if ccache is installed)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${CLANG_DIR:?CLANG_DIR must point to an AOSP clang prebuilt}"
OUT="${OUT:-$ROOT/out}"
KSU="${KSU:-true}"
KSU_REF="${KSU_REF:-builtin}"
SUSFS="${SUSFS:-true}"
JOBS="${JOBS:-$(nproc)}"
if [ -z "${USE_CCACHE:-}" ]; then
	command -v ccache >/dev/null && USE_CCACHE=true || USE_CCACHE=false
fi

export PATH="$CLANG_DIR/bin:$PATH"
export KBUILD_BUILD_USER="sukisu-nova"
export KBUILD_BUILD_HOST="github-actions"

echo "== clang: $(clang --version | head -n1)"
echo "== KSU=$KSU KSU_REF=$KSU_REF SUSFS=$SUSFS JOBS=$JOBS CCACHE=$USE_CCACHE"

# Fixed version suffix (avoids "-dirty" from KernelSU setup touching drivers/)
echo "-g$(git rev-parse --short=12 HEAD)" > .scmversion

# ---------------------------------------------------------------------------
# SukiSU-Nova: official setup.sh from builtin branch, tracking the given ref
# ---------------------------------------------------------------------------
if [ "$KSU" = "true" ]; then
	if [ ! -d KernelSU ]; then
		curl -LSs "https://raw.githubusercontent.com/SukiSU-Nova/SukiSU-Nova/builtin/kernel/setup.sh" | bash -s "$KSU_REF"
	else
		echo "== KernelSU already present, checking out $KSU_REF"
		git -C KernelSU fetch --tags origin
		git -C KernelSU checkout -q "$KSU_REF"
		git -C KernelSU pull -q --ff-only || true
	fi
	echo "== SukiSU-Nova commit: $(git -C KernelSU rev-parse HEAD)"

	# Patch SukiSU-Nova (builtin) for Linux 4.14 non-GKI compatibility:
	# 1. <linux/static_call.h> only exists on 5.10+ (and is unused in KernelSU)
	sed -i '/#include <linux\/static_call.h>/d' KernelSU/kernel/kernel_includes.h
	# 2. Linux 4.14 access_ok() takes 3 arguments; use ksu_access_ok() wrapper from kernel_compat.h
	sed -i 's/!access_ok(/!ksu_access_ok(/g' KernelSU/kernel/extension/kpm/kpm.c
	# 3. Qualcomm 4.14 backported task_struct->thread_pid from 4.19 (replacing pids[PIDTYPE_PID])
	sed -i 's/LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0)/LINUX_VERSION_CODE < KERNEL_VERSION(4, 14, 0)/g' KernelSU/kernel/extension/kpm/super_access.c
fi

# ---------------------------------------------------------------------------
# Toolchain flags (same style as LineageOS: LLVM=1 LLVM_IAS=1)
# ---------------------------------------------------------------------------
CC_BIN="clang"
[ "$USE_CCACHE" = "true" ] && CC_BIN="ccache clang"

MAKE_ARGS=(
	-C "$ROOT"
	O="$OUT"
	ARCH=arm64
	LLVM=1
	LLVM_IAS=1
	CC="$CC_BIN"
	HOSTCC=clang
	HOSTCXX=clang++
	CROSS_COMPILE=aarch64-linux-gnu-
	CROSS_COMPILE_ARM32=arm-linux-gnueabi-
	CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
	CLANG_TRIPLE=aarch64-linux-gnu-
)

mkdir -p "$OUT"
DEFCONFIGS="vendor/sdmsteppe-perf_defconfig vendor/davinci.config vendor/minatok20.config vendor/minatok20_stage2.config vendor/minatok20_stage3.config"
# The SUSFS feature flags live in a fragment so the exact feature set is
# pinned (and sus_kstat/sus_map/open_redirect/sus_mount stay off on 4.14).
if [ "$KSU" = "true" ] && [ "$SUSFS" = "true" ]; then
	DEFCONFIGS="$DEFCONFIGS vendor/minatok20_susfs.config"
fi
make "${MAKE_ARGS[@]}" $DEFCONFIGS

CFG="$ROOT/scripts/config --file $OUT/.config"
if [ "$KSU" = "true" ]; then
	$CFG -e KSU -e KPM -e KSU_FEATURE_ADBROOT
	if [ "$SUSFS" = "true" ]; then
		$CFG -e KSU_SUSFS -e KSU_SUSFS_PRIORITY_UID_FILTER
	else
		$CFG -d KSU_SUSFS
	fi
else
	$CFG -d KSU
fi
make "${MAKE_ARGS[@]}" olddefconfig

# Verify the selected options survived olddefconfig
if [ "$KSU" = "true" ]; then
	grep -q '^CONFIG_KSU=y' "$OUT/.config" || { echo "CONFIG_KSU not enabled"; exit 1; }
	grep -q '^CONFIG_KPM=y' "$OUT/.config" || { echo "CONFIG_KPM not enabled"; exit 1; }
	if [ "$SUSFS" = "true" ]; then
		grep -q '^CONFIG_KSU_SUSFS=y' "$OUT/.config" || { echo "CONFIG_KSU_SUSFS not enabled"; exit 1; }
		grep -q '^CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y' "$OUT/.config" || { echo "CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER not enabled"; exit 1; }
	else
		if grep -q '^CONFIG_KSU_SUSFS=y' "$OUT/.config"; then
			echo "CONFIG_KSU_SUSFS should be disabled when SUSFS=false"; exit 1
		fi
	fi
fi
for opt in AUDIT KALLSYMS KALLSYMS_ALL; do
	grep -q "^CONFIG_${opt}=y" "$OUT/.config" || { echo "CONFIG_${opt} must stay enabled"; exit 1; }
done
if grep -q '^CONFIG_ZRAM_WRITEBACK=y' "$OUT/.config"; then
	echo "CONFIG_ZRAM_WRITEBACK must stay disabled"; exit 1
fi

make "${MAKE_ARGS[@]}" -j"$JOBS"

ls -l "$OUT/arch/arm64/boot/Image.gz"
echo "== Kernel release: $(cat "$OUT/include/config/kernel.release")"
