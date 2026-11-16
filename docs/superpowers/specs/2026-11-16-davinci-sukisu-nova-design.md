# Design Doc: `davinci-sukisu-nova-kernel` (Redmi K20 / Mi 9T — LineageOS 23.2)

## 1. Intent & Why
Create a brand-new, standalone GitHub repository (`20032773/davinci-sukisu-nova-kernel`) for the Xiaomi Mi 9T / Redmi K20 (`davinci`, Snapdragon 730 / `sm6150`, Linux 4.14.357-openela) targeting **LineageOS 23.2 (Android 16)**, without touching or overwriting the existing working `minatok20-susfs` branch in `20032773/android_kernel_xiaomi_sm6150`.

The new kernel replaces BakaSU with **SukiSU-Nova (`SukiSU-Nova/SukiSU-Nova`, `builtin` branch)** + **SUSFS v2.4.0** + **KPM**, while integrating safe, non-overclocking performance, memory, stealth, and power optimizations.

## 2. Goals, Non-Goals & Anti-Goals
- **Goals:**
  - Standalone GitHub repository (`20032773/davinci-sukisu-nova-kernel`) with automated GitHub Actions build + AnyKernel3 packaging (`Image.gz`, `dtb`, `dtbo.img`) + companion `gamemode` WebUI module.
  - Integrate `SukiSU-Nova/SukiSU-Nova` (`builtin` branch) with full SUSFS v2.4.0 inline hooks (`sus_path`, `spoof_uname`, `spoof_cmdline`, `hide_ksu_susfs_symbols`, `priority_uid_filter`, `enable_log`, `try_umount` via backported `path_umount`) and SukiSU-Nova features (`CONFIG_KPM=y`, `CONFIG_KSU_FEATURE_ADBROOT=y`).
  - Retain all proven `minatok20-susfs` optimizations: Sultan's `cpu_input_boost` & `devfreq_boost` (clamped to stock max), KCAL RGB/PCC color control, `xiaomi_touch` hardware `touch_mode` sysfs node, TCP BBR + `fq` default, ZRAM LZ4 default, `CONFIG_ZRAM_WRITEBACK=n`, `CONFIG_IPC_LOGGING=n`.
  - Add new safe non-overclock optimizations & stealth improvements:
    1. **Stealth (`/proc/<pid>/maps` & `map_files`)**: Port `69_hide_stuff.patch` (`fs/proc/task_mmu.c`, `fs/proc/base.c`) to spoof `"lineage"` paths as `/system/framework/framework-res.apk` and strip executable flag display on `"jit-zygote-cache"`.
    2. **Kernel Debloat (Zero-Risk Hot-Path Cleanup)**: Disable `CONFIG_SLUB_DEBUG`, `CONFIG_SCHED_DEBUG`, `CONFIG_QCOM_RTB`, `CONFIG_BLK_DEV_IO_TRACE` while keeping `CONFIG_AUDIT=y`, `CONFIG_KALLSYMS=y`, `CONFIG_KALLSYMS_ALL=y`, `CONFIG_FTRACE=y`.
    3. **Kryo 470 (ARMv8.2-A) Compiler Tuning**: Add `-mcpu=cortex-a76.cortex-a55` (or `-march=armv8.2-a+crypto+fp16+dotprod`) in `arch/arm64/Makefile` when supported by Clang.
    4. **Scheduler & RCU Power Efficiency**: Enable `CONFIG_RCU_BOOST=y` (if not already enabled) to prevent RCU reader stalls under heavy UI load without raising clocks.
- **Non-Goals / Anti-Goals:**
  - **No overclocking** of CPU, GPU, DDR bus, or display refresh rate; no undervolting/overvolting or thermal limit relaxation.
  - **No risky 4.14 KABI / filesystem rewrites**: Skip `ThinLTO` (causes instability/reboots on this 4.14 tree), skip `f2fs-stable` backports (data corruption risk), skip `MGLRU`, and skip `sus_kstat` / `sus_mount` mnt_id-rework that cause 4.14 bootloops.

## 3. Approaches Considered
- **Approach A (Selected — Stable Full-Featured Build):**
  Build upon the proven `minatok20-susfs` baseline, switch the root engine to `SukiSU-Nova/SukiSU-Nova` (`builtin` branch), reconcile the 3 hook/Kconfig ABI differences between BakaSU and SukiSU-Nova, and layer on `/proc/maps` stealth (`69_hide_stuff`), kernel debug debloat (`SLUB_DEBUG` / `SCHED_DEBUG` / `QCOM_RTB` off), `priority_uid_filter`, `KPM`, and Kryo 470 compiler tuning.
- **Approach B (Rejected — Experimental ThinLTO + kstat Rework):**
  Also port `ThinLTO` (`patch_thinlto_kbuild.py`) and `struct kstat` modifications from `Redmi-K20-kernel-test`. Rejected because the user confirmed `Redmi-K20-kernel-test` suffered from random reboots and instability.

## 4. Key Technical Changes for SukiSU-Nova (`builtin`) Compatibility
1. **`fs/exec.c`:**
   - Under `CONFIG_KSU_SUSFS`, `SukiSU-Nova` (`builtin`) names the post-execveat handler `ksu_handle_post_execveat_sucompat(...)` instead of `ksu_handle_post_execveat(...)`.
   - When `CONFIG_KSU_SUSFS` is disabled (manual hook fallback on `builtin`), only `ksu_handle_execveat(...)` is called before `__do_execve_file`.
2. **`fs/open.c` & `fs/stat.c`:**
   - `SukiSU-Nova` (`builtin`) defines `bool ksu_su_compat_enabled __read_mostly = true;` instead of `struct static_key_true ksu_su_compat_enabled`. Replace `static_branch_likely(&ksu_su_compat_enabled)` with `likely(ksu_su_compat_enabled)`.
3. **Manual Hook Fallback Guards (`CONFIG_KSU_MANUAL_HOOK` removal):**
   - `SukiSU-Nova` (`builtin`) removed `CONFIG_KSU_MANUAL_HOOK` from `Kconfig`. Update `#ifdef CONFIG_KSU_MANUAL_HOOK` guards in `fs/exec.c`, `fs/open.c`, `fs/stat.c`, `fs/read_write.c`, `drivers/input/input.c`, and `kernel/reboot.c` to `#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)` so both `susfs=true` and `susfs=false` workflow builds compile cleanly.
4. **Build Script & Config Fragments (`minatok20/build.sh`, `arch/arm64/configs/vendor/`):**
   - Clone `https://github.com/SukiSU-Nova/SukiSU-Nova` (default branch `builtin`).
   - Enable `CONFIG_KPM=y`, `CONFIG_KSU_FEATURE_ADBROOT=y`, and `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y`.
   - Add stage-3 optimization fragment (`minatok20_stage3.config`) disabling `SLUB_DEBUG`, `SCHED_DEBUG`, `QCOM_RTB`, `BLK_DEV_IO_TRACE`.
