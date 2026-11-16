# Xiaomi Mi 9T / Redmi K20 (`davinci`) SukiSU-Nova Stage 4 Deep Optimization Design Spec

- **Date**: 2026-11-16
- **Target Repository**: `20032773/davinci-sukisu-nova-kernel` (`main` branch)
- **Target Device**: Xiaomi Mi 9T / Redmi K20 (`davinci`, Snapdragon 730 / `sm6150`, Kryo 470, Adreno 618)
- **Target OS**: LineageOS 23.2 (Android 16)
- **Hard Constraints**:
  - **Zero Overclocking**: Do not increase CPU, GPU, DDR bus, or display refresh frequencies; do not alter voltage tables or thermal throttling thresholds.
  - **100% Boot & F2FS Stability**: Do not modify `struct kstat` layout on Linux 4.14 (preserve ABI compatibility), do not disable `CONFIG_FTRACE`/`CONFIG_AUDIT`/`CONFIG_KALLSYMS`, and do not touch experimental `f2fs-stable` backports.

---

## 1. Category A: SUSFS v2.4.0 Deep Stealth Completion (`sus_map`, `open_redirect`, `sus_kstat`)

### 1.1 Overview
`fs/susfs.c` already contains the full SUSFS v2.4.0 hash tables, RCU/SRCU locks, and userspace `prctl` handlers for `sus_map`, `open_redirect`, and `sus_kstat`. By adapting `susfs_mark_inode_sus_kstat()` to use 4.14's native `real_mount(path.mnt)->mnt_id` and `vfs_statfs(&path, ...)` (matching `susfs_add_open_redirect()`) and wiring the VFS call sites, all three advanced SUSFS features can be safely enabled on Linux 4.14 without changing `struct kstat`.

### 1.2 Detailed Changes
1. **`fs/susfs.c`**:
   - Declare/export internal helper prototypes in `include/linux/susfs.h` so `fs/stat.c`, `fs/statfs.c`, `fs/open.c`, `fs/namei.c`, `fs/proc/base.c`, `fs/proc/fd.c`, and `fs/proc/task_mmu.c` can invoke them without implicit declaration errors.
   - In `susfs_mark_inode_sus_kstat()`, replace calls to `sus_mount`-only helpers (`susfs_get_non_sus_mnt_id_from_mnt`, `susfs_get_non_sus_vfsmnt_from_vfsmnt`, `statfs_by_dentry_wrapper`, `calculate_f_flags_wrapper`) with `real_mount(path.mnt)->mnt_id` and `vfs_statfs(&path, &new_entry->spoofed_kstatfs)`.
2. **`fs/stat.c` (`vfs_getattr_nosec`)**:
   - Under `CONFIG_KSU_SUSFS_SUS_KSTAT`, after `getattr` or `generic_fillattr` succeeds, if `susfs_is_current_proc_umounted_app()` and `susfs_is_inode_sus_kstat(inode, &is_fuse)` are true, call `susfs_sus_kstat_spoof_generic_fillattr(inode, stat, is_fuse ? STATX_SUS_KSTAT_FUSE : STATX_SUS_KSTAT)`.
3. **`fs/statfs.c` (`vfs_statfs`)**:
   - Under `CONFIG_KSU_SUSFS_SUS_KSTAT`, if `susfs_is_current_proc_umounted_app()` and `susfs_is_inode_sus_kstat(inode, &is_fuse)` are true, spoof `buf` via `susfs_sus_kstat_spoof_vfs_statfs(inode, buf, &is_fuse)`.
4. **`fs/open.c` (`do_sys_open`)**:
   - Under `CONFIG_KSU_SUSFS_OPEN_REDIRECT`, when opening an existing file (`!(flags & O_CREAT)`), check if the target inode has `AS_FLAGS_OPEN_REDIRECT` set via `SUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(inode)`. If so, call `susfs_open_redirect_spoof_do_sys_openat(inode)` and replace `tmp` with the redirected `struct filename *`.
5. **`fs/namei.c` (`vfs_readlink`) & `fs/proc/base.c` (`do_proc_readlink`)**:
   - Under `CONFIG_KSU_SUSFS_OPEN_REDIRECT`, if `SUSFS_IS_INODE_OPEN_REDIRECT(inode)` is true, spoof symlink/fd readlink resolution back to the original `target_pathname`.
6. **`fs/proc/fd.c` (`seq_show`)**:
   - Under `CONFIG_KSU_SUSFS_SUS_KSTAT`, if `susfs_is_current_proc_umounted_app()` and `susfs_is_inode_sus_kstat(inode, &is_fuse)` are true, spoof `mnt_id` in `/proc/<pid>/fdinfo/<fd>`.
7. **`fs/proc/task_mmu.c` (`show_map_vma`, `show_smap`, `pte_to_pagemap_entry`)**:
   - `CONFIG_KSU_SUSFS_SUS_MAP`: Hide VMAs whose backing inode matches `SUSFS_IS_INODE_SUS_MAP(inode)` in `/proc/<pid>/maps`, `/proc/<pid>/smaps`, `/proc/<pid>/smaps_rollup`, and zero out their entries in `/proc/<pid>/pagemap`.
   - `CONFIG_KSU_SUSFS_SUS_KSTAT`: Spoof `dev` and `ino` in `show_map_vma` via `susfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino)`.
   - `CONFIG_KSU_SUSFS_OPEN_REDIRECT`: Spoof `ino`, `dev`, and `name` in `show_map_vma` via `susfs_open_redirect_spoof_show_map_vma_srcu`.
8. **`arch/arm64/configs/vendor/minatok20_susfs.config`**:
   - Enable `CONFIG_KSU_SUSFS_SUS_KSTAT=y`, `CONFIG_KSU_SUSFS_SUS_MAP=y`, and `CONFIG_KSU_SUSFS_OPEN_REDIRECT=y`.

---

## 2. Category B: Memory (VM), ZRAM & UFS Block Queue Optimization

1. **ZRAM Zero Swap Readahead (`mm/swap.c`)**:
   - Set `page_cluster = 0;` in `swap_setup()`. Since `davinci` uses in-RAM LZ4 ZRAM swap rather than a rotational disk, multi-page readahead (`page_cluster = 3`, 8 pages) wastes CPU decompressing adjacent unrelated swap slots and increases page-fault latency.
2. **Disable Default Block Queue `iostats` & `add_random` Overhead (`include/linux/blkdev.h`)**:
   - Remove `(1 << QUEUE_FLAG_IO_STAT)` and `(1 << QUEUE_FLAG_ADD_RANDOM)` from `QUEUE_FLAG_DEFAULT` and `QUEUE_FLAG_MQ_DEFAULT` so UFS 2.1 and ZRAM request queues skip per-I/O timestamp/accounting and entropy lock contention.
3. **TCP BBR Responsiveness Tuning (`net/ipv4/tcp_bbr.c`)**:
   - Reduce `bbr_min_rtt_win_sec` from `10` to `5` seconds and `bbr_probe_rtt_mode_ms` from `200` to `100` ms so BBR adapts faster to Wi-Fi / cellular RTT changes with shorter probe pauses.

---

## 3. Category C: Xiaomi Mi 9T (`davinci`) Hardware Power & Display Enhancements

1. **Adreno 618 Fast GPU Nap (`drivers/gpu/msm/adreno.c` & `arch/arm64/boot/dts/...`)**:
   - Clamp `timeout` in `adreno_of_read_property()` (`drivers/gpu/msm/adreno.c`) to a maximum of `58` ms (down from Qualcomm's default `80` ms). The GPU enters deep sleep 22 ms sooner after completing a frame, reducing idle power draw and heat with zero frequency/voltage changes.
2. **Kernel-Space Qualcomm Wakelock Blocker (`drivers/base/power/wakeup.c`)**:
   - Filter high-drain spurious Qualcomm Wi-Fi/IPA/diag wakelocks (`qcom_rx_wakelock`, `wlan_pno_wl`, `wlan_extscan_wl`, `NETLINK`, `ipa_WS`, `timerfd`) in `wakeup_source_activate()`, preventing unnecessary background suspend aborts while preserving all critical system wakelocks.
3. **Enhanced 3-Level Display HBM Control (`drivers/gpu/drm/msm/dsi-staging/dsi_panel.c`)**:
   - Extend `dsi_panel_apply_hbm_mode()` so `/sys/devices/platform/soc/soc:qcom,dsi-display/hbm` supports `0` (HBM Off), `1` (Standard Sunlight HBM), and `2` (Peak FOD HBM `DSI_CMD_SET_DISP_HBM_FOD_ON`), properly sending `DSI_CMD_SET_DISP_HBM_FOD_OFF` when returning to `0`.

---

## 4. Category D: ARM64 Microarchitecture & Scheduler Refinements

1. **ARM64 Optimized `csum_ipv6_magic` & Word-Parallel `strchr`/`memchr` (`arch/arm64/include/asm/checksum.h`, `arch/arm64/lib/`)**:
   - Add ARM Ltd's inline assembly `csum_ipv6_magic()` to `arch/arm64/include/asm/checksum.h` for hardware-accelerated 64-bit carry-chain IPv6 TCP/UDP checksums.
2. **Scheduler `iowait_boost` Capping & Decay Refinement (`kernel/sched/cpufreq_schedutil.c`)**:
   - In `sugov_set_iowait_boost()`, start initial `iowait_boost` at `min` frequency instead of jumping aggressively, and cap `iowait_boost_max` on big cores so background disk/cache writes do not spike Cortex-A76 cores to 2.2 GHz unnecessarily.
