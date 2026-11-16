# Xiaomi Mi 9T / Redmi K20 (`davinci`) Stage 4 Deep Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Categories A (SUSFS v2.4.0 full stealth: `sus_map`, `open_redirect`, `sus_kstat`), B (VM ZRAM `page-cluster = 0`, Block queue `iostats`/`add_random` removal, TCP BBR tuning), C (`davinci` Adreno 618 58ms fast nap, Qualcomm wakelock blocker, 3-level HBM control), and D (ARM64 `csum_ipv6_magic` inline assembly & scheduler `iowait_boost` big-core cap) into `20032773/davinci-sukisu-nova-kernel`.

**Architecture:** Clean, modular in-tree patches across VFS/procfs (`fs/`), memory/block/network (`mm/`, `include/linux/blkdev.h`, `net/ipv4/tcp_bbr.c`), hardware drivers (`drivers/gpu/msm/`, `drivers/base/power/`, `drivers/gpu/drm/msm/dsi-staging/`), and ARM64/scheduler (`arch/arm64/include/asm/checksum.h`, `kernel/sched/cpufreq_schedutil.c`), preserving 4.14 ABI and hardware clock/voltage/thermal limits.

**Tech Stack:** Linux 4.14.357 (`sm6150`), Clang r563880c (AOSP Prebuilt), GitHub Actions CI + AnyKernel3.

---

### Task 1: Category A — SUSFS v2.4.0 `sus_kstat`, `open_redirect`, and `sus_map` Integration

**Files:**
- Modify: `repo/include/linux/susfs.h`
- Modify: `repo/fs/susfs.c`
- Modify: `repo/fs/stat.c`
- Modify: `repo/fs/statfs.c`
- Modify: `repo/fs/open.c`
- Modify: `repo/fs/namei.c`
- Modify: `repo/fs/proc/base.c`
- Modify: `repo/fs/proc/fd.c`
- Modify: `repo/fs/proc/task_mmu.c`
- Modify: `repo/arch/arm64/configs/vendor/minatok20_susfs.config`

- [ ] **Step 1: Update `include/linux/susfs.h` and `fs/susfs.c` for 4.14 `sus_kstat`, `open_redirect`, and `sus_map`**
  - Add helper declarations in `include/linux/susfs.h` (`susfs_is_inode_sus_kstat`, `susfs_sus_kstat_spoof_generic_fillattr`, `susfs_sus_kstat_spoof_show_map_vma`, `susfs_sus_kstat_spoof_vfs_statfs`, `susfs_sus_kstat_spoof_proc_fd_seq_show`, `susfs_open_redirect_spoof_do_sys_openat`, `susfs_open_redirect_spoof_vfs_readlink`, `susfs_open_redirect_spoof_do_proc_readlink`, `susfs_open_redirect_spoof_show_map_vma_srcu`).
  - Update `susfs_mark_inode_sus_kstat()` in `fs/susfs.c` to use `real_mount(path.mnt)->mnt_id` and `vfs_statfs(&path, &new_entry->spoofed_kstatfs)` instead of `sus_mount`-only externs.
- [ ] **Step 2: Wire `sus_kstat` in `fs/stat.c`, `fs/statfs.c`, and `fs/proc/fd.c`**
  - Hook `vfs_getattr_nosec()` in `fs/stat.c`, `vfs_statfs()` in `fs/statfs.c`, and `seq_show()` in `fs/proc/fd.c`.
- [ ] **Step 3: Wire `open_redirect` in `fs/open.c`, `fs/namei.c`, and `fs/proc/base.c`**
  - Hook `do_sys_open()` in `fs/open.c`, `vfs_readlink()` in `fs/namei.c`, and `do_proc_readlink()` in `fs/proc/base.c`.
- [ ] **Step 4: Wire `sus_map`, `sus_kstat`, and `open_redirect` in `fs/proc/task_mmu.c` and enable Kconfig flags**
  - Hook `show_map_vma()`, `show_smap()`, and `pte_to_pagemap_entry()` in `fs/proc/task_mmu.c`.
  - Enable `CONFIG_KSU_SUSFS_SUS_KSTAT=y`, `CONFIG_KSU_SUSFS_SUS_MAP=y`, and `CONFIG_KSU_SUSFS_OPEN_REDIRECT=y` in `arch/arm64/configs/vendor/minatok20_susfs.config`.

---

### Task 2: Category B — VM ZRAM, Block Queue & TCP BBR Deep Optimization

**Files:**
- Modify: `repo/mm/swap.c`
- Modify: `repo/include/linux/blkdev.h`
- Modify: `repo/net/ipv4/tcp_bbr.c`

- [ ] **Step 1: Set `page_cluster = 0` in `mm/swap.c`**
  - Default swap readahead to 0 (1 page) in `swap_setup()` for low-latency LZ4 ZRAM page-ins.
- [ ] **Step 2: Strip `QUEUE_FLAG_IO_STAT` and `QUEUE_FLAG_ADD_RANDOM` from default block queue flags in `include/linux/blkdev.h`**
  - Eliminate per-I/O accounting and entropy lock contention on UFS 2.1 and ZRAM queues.
- [ ] **Step 3: Tune TCP BBR RTT window and probe duration in `net/ipv4/tcp_bbr.c`**
  - Set `bbr_min_rtt_win_sec = 5` and `bbr_probe_rtt_mode_ms = 100`.

---

### Task 3: Category C — Xiaomi Mi 9T (`davinci`) Hardware Power & Display Enhancements

**Files:**
- Modify: `repo/drivers/gpu/msm/adreno.c`
- Modify: `repo/drivers/base/power/wakeup.c`
- Modify: `repo/drivers/gpu/drm/msm/dsi-staging/dsi_panel.c`

- [ ] **Step 1: Lower Adreno 618 GPU idle timeout to 58ms in `drivers/gpu/msm/adreno.c`**
  - Clamp `timeout` in `adreno_of_read_property()` to `58` ms so the GPU enters Nap state 22ms sooner after frame completion.
- [ ] **Step 2: Block spurious Qualcomm wakelocks in `drivers/base/power/wakeup.c`**
  - Filter `qcom_rx_wakelock`, `wlan_pno_wl`, `wlan_extscan_wl`, `ipa_WS`, and `NETLINK` in `wakeup_source_activate()`.
- [ ] **Step 3: Extend `dsi_panel_apply_hbm_mode()` in `drivers/gpu/drm/msm/dsi-staging/dsi_panel.c`**
  - Support `hbm = 0` (Off), `1` (Normal HBM), and `2` (Peak FOD HBM).

---

### Task 4: Category D — ARM64 Checksum Assembly & Scheduler `iowait_boost` Refinement

**Files:**
- Modify: `repo/arch/arm64/include/asm/checksum.h`
- Modify: `repo/kernel/sched/cpufreq_schedutil.c`

- [ ] **Step 1: Implement ARM64 inline assembly `csum_ipv6_magic` in `arch/arm64/include/asm/checksum.h`**
  - Port upstream ARM Ltd 64-bit carry-chain assembly implementation of `csum_ipv6_magic()`.
- [ ] **Step 2: Cap big-cluster `iowait_boost_max` in `kernel/sched/cpufreq_schedutil.c`**
  - Cap `iowait_boost_max` on big Cortex-A76 cores (`!cpumask_test_cpu(cpu, cpu_lp_mask)`) to `1497600` kHz (~1.5 GHz) so background disk writes don't spike big cores to 2.2 GHz.

---

### Task 5: Cloud Build, Packaging & Verification

- [ ] **Step 1: Commit and push all changes to `20032773/davinci-sukisu-nova-kernel` (`main`)**
- [ ] **Step 2: Monitor GitHub Actions build to completion and download the flashable AnyKernel3 ZIP**
