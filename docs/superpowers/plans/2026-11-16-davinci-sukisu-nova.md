# `davinci-sukisu-nova-kernel` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the standalone GitHub repository `20032773/davinci-sukisu-nova-kernel` for Xiaomi Mi 9T / Redmi K20 (`davinci`, LineageOS 23.2, Linux 4.14.357-openela) integrating `SukiSU-Nova` (`builtin` branch) + SUSFS v2.4.0 + KPM and safe non-overclock optimizations, verified via GitHub Actions cloud build.

**Architecture:** Start from the proven `minatok20-susfs` baseline (`20032773/android_kernel_xiaomi_sm6150@minatok20-susfs`), replace BakaSU with `SukiSU-Nova/SukiSU-Nova` (`builtin` branch), reconcile the 3 hook/Kconfig ABI differences (`ksu_handle_post_execveat_sucompat`, `bool ksu_su_compat_enabled`, and `#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)`), wire up `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` in `kernel/sys.c` and `block/ioprio.c`, add `/proc/<pid>/maps` & `map_files` LineageOS/Zygote hiding (`69_hide_stuff`), add Stage 3 non-overclock optimization config (`SLUB_DEBUG` / `SCHED_DEBUG` / `QCOM_RTB` / `BLK_DEV_IO_TRACE` disabled, `RCU_BOOST` enabled) and Kryo 470 (`-mcpu=cortex-a76.cortex-a55`) compiler tuning, and push to the new standalone GitHub repository.

**Tech Stack:** Linux Kernel 4.14 (C / Kbuild / Kconfig), AOSP Clang `clang-r563880c`, SukiSU-Nova (`builtin`), SUSFS v2.4.0, AnyKernel3, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-16-davinci-sukisu-nova-design.md`

## Global Constraints

- No overclocking of CPU, GPU, DDR bus, or display refresh rate; no voltage or thermal limit relaxation.
- Keep `CONFIG_AUDIT=y`, `CONFIG_KALLSYMS=y`, `CONFIG_KALLSYMS_ALL=y`, `CONFIG_FTRACE=y`, and `CONFIG_ZRAM_WRITEBACK=n`.
- Do not enable `ThinLTO`, `MGLRU`, `f2fs-stable` backports, or `sus_kstat` / `sus_mount` mnt_id spoofing on 4.14.
- Leave original repository `20032773/android_kernel_xiaomi_sm6150` completely untouched; push all work to new standalone repository `20032773/davinci-sukisu-nova-kernel`.

## Review Focus

- `SukiSU-Nova` (`builtin` branch) defines `ksu_handle_post_execveat_sucompat` only when `CONFIG_KSU_SUSFS=y`; calling `ksu_handle_post_execveat` or calling it when `CONFIG_KSU_SUSFS` is off will cause an undefined symbol linker error.
- `SukiSU-Nova` (`builtin` branch) defines `bool ksu_su_compat_enabled` rather than `struct static_key_true ksu_su_compat_enabled`; `fs/open.c` and `fs/stat.c` must use `extern bool ksu_su_compat_enabled;` and `likely(ksu_su_compat_enabled)`.
- `SukiSU-Nova` (`builtin` branch) does not define `CONFIG_KSU_MANUAL_HOOK` in `Kconfig`; manual-hook fallback blocks and `minatok20/build.sh` verification checks must use `#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)` instead of requiring `CONFIG_KSU_MANUAL_HOOK=y`.
- `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y` requires `susfs_is_priority_uid_filtered(uid_t uid)` to be declared and called in `kernel/sys.c` (`setpriority`, `getpriority`) and `block/ioprio.c` (`ioprio_set`, `ioprio_get`).
- Windows NTFS case-insensitivity collides on `include/uapi/linux/netfilter/xt_*.h` during a full working-tree checkout; use `git clone --no-checkout` + `git sparse-checkout` so the Git index retains all 70,000+ kernel files while only checking out the modified paths on disk.

---

### Task 1: Initialize Standalone Repository & Sparse Working Tree

**Files:**
- Create: `20032773/davinci-sukisu-nova-kernel` (GitHub repository)
- Checkout (sparse): `arch/arm64/Makefile`, `arch/arm64/configs/vendor/`, `block/ioprio.c`, `drivers/input/input.c`, `fs/`, `include/linux/`, `kernel/`, `minatok20/`, `.github/workflows/build.yml`, `README.md`

**Interfaces:**
- Consumes: `https://github.com/20032773/android_kernel_xiaomi_sm6150.git` (`minatok20-susfs` branch)
- Produces: Local git repository at `d:\ai agent\k20 kernel\repo` with remote `origin` pointing to `https://github.com/20032773/davinci-sukisu-nova-kernel.git`

- [ ] **Step 1: Create new GitHub repository `20032773/davinci-sukisu-nova-kernel`**

Run: `gh repo create 20032773/davinci-sukisu-nova-kernel --public --description "Custom Linux 4.14 kernel for Xiaomi Mi 9T / Redmi K20 (davinci) on LineageOS 23.2 with SukiSU-Nova, SUSFS v2.4.0, KPM, and safe non-overclock optimizations"`
Expected: Repository URL `https://github.com/20032773/davinci-sukisu-nova-kernel` printed.

- [ ] **Step 2: Clone `minatok20-susfs` with `--no-checkout` and configure sparse checkout**

Run:
```powershell
git clone --no-checkout --single-branch --branch minatok20-susfs https://github.com/20032773/android_kernel_xiaomi_sm6150.git repo
cd repo
git sparse-checkout init --no-cone
git sparse-checkout set /README.md /.gitignore /.github/ /arch/arm64/Makefile /arch/arm64/configs/vendor/ /block/ioprio.c /drivers/input/input.c /fs/ /include/linux/susfs.h /include/linux/susfs_def.h /kernel/ /minatok20/
git checkout minatok20-susfs
```
Expected: Working tree populated with target directories without NTFS case-collision warnings; `git status` shows clean working tree.

---

### Task 2: Reconcile SukiSU-Nova (`builtin`) Kernel Hooks & Priority UID Filter

**Files:**
- Modify: `repo/fs/exec.c`
- Modify: `repo/fs/open.c`
- Modify: `repo/fs/stat.c`
- Modify: `repo/fs/read_write.c`
- Modify: `repo/drivers/input/input.c`
- Modify: `repo/kernel/reboot.c`
- Modify: `repo/kernel/sys.c`
- Modify: `repo/block/ioprio.c`
- Modify: `repo/include/linux/susfs.h`

**Interfaces:**
- Consumes: `SukiSU-Nova` (`builtin` branch) exports:
  - `int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);`
  - `int ksu_handle_post_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv_user, void *envp_user, int *flags, int *retval);` (under `#ifdef CONFIG_KSU_SUSFS`)
  - `extern bool ksu_su_compat_enabled;`
  - `bool susfs_is_priority_uid_filtered(uid_t uid);` (defined in `fs/susfs.c` under `#ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`)
- Produces: Cleanly compiling hook call sites for both `CONFIG_KSU_SUSFS=y` and `CONFIG_KSU_SUSFS=n` (manual hook fallback).

- [ ] **Step 1: Update `fs/exec.c`, `fs/open.c`, `fs/stat.c`, `fs/read_write.c`, `drivers/input/input.c`, and `kernel/reboot.c` for SukiSU-Nova (`builtin`)**

In `fs/exec.c`:
- Guard manual hook + SUSFS with `#ifdef CONFIG_KSU`.
- Call `ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);` before `__do_execve_file`.
- Under `#ifdef CONFIG_KSU_SUSFS`, declare and call `ksu_handle_post_execveat_sucompat(&fd, &filename, &argv, &envp, &flags, &retval);` after `__do_execve_file`.

In `fs/open.c` and `fs/stat.c`:
- Change `extern struct static_key_true ksu_su_compat_enabled;` to `extern bool ksu_su_compat_enabled;` and `if (static_branch_likely(&ksu_su_compat_enabled))` to `if (likely(ksu_su_compat_enabled))`.
- Replace `#ifdef CONFIG_KSU_MANUAL_HOOK` with `#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)`.

In `fs/read_write.c` and `drivers/input/input.c`:
- Keep `#ifdef CONFIG_KSU_SUSFS` static-branch hooks, and add `#elif defined(CONFIG_KSU)` manual-hook fallback calling `ksu_handle_vfs_read` / `ksu_handle_input_handle_event`.

In `kernel/reboot.c`:
- Replace `#if defined(CONFIG_KSU_MANUAL_HOOK) || defined(CONFIG_KSU_SUSFS)` with `#ifdef CONFIG_KSU`.

- [ ] **Step 2: Wire `susfs_is_priority_uid_filtered` in `include/linux/susfs.h`, `kernel/sys.c`, and `block/ioprio.c`**

In `include/linux/susfs.h` (under `#ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`):
- Add `bool susfs_is_priority_uid_filtered(uid_t uid);`.

In `kernel/sys.c` (`setpriority` and `getpriority`, inside `case PRIO_USER:` -> `else if (!uid_eq(uid, cred->uid))`):
- Add:
```c
#ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER
			if (cred->uid.val >= 10000 && susfs_is_priority_uid_filtered(uid.val))
				goto out_unlock;
#endif
```

In `block/ioprio.c` (`ioprio_set` and `ioprio_get`, inside `case IOPRIO_WHO_USER:`):
- Add:
```c
#ifdef CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER
			if (current_uid().val >= 10000 && susfs_is_priority_uid_filtered(uid.val))
				break;
#endif
```

- [ ] **Step 3: Verify hook symbols match `SukiSU-Nova` (`builtin`)**

Run: `Select-String -Path repo/fs/exec.c,repo/fs/open.c,repo/fs/stat.c,repo/kernel/sys.c,repo/block/ioprio.c -Pattern "ksu_handle_post_execveat_sucompat|ksu_su_compat_enabled|susfs_is_priority_uid_filtered"`
Expected: Matches in all 5 files with zero remaining references to `ksu_handle_post_execveat(` or `CONFIG_KSU_MANUAL_HOOK`.

---

### Task 3: Add Stage-3 Stealth (`69_hide_stuff`) & Non-Overclock Kernel Optimizations

**Files:**
- Modify: `repo/fs/proc/task_mmu.c`
- Modify: `repo/fs/proc/base.c`
- Modify: `repo/arch/arm64/Makefile`
- Create: `repo/arch/arm64/configs/vendor/minatok20_stage3.config`
- Modify: `repo/arch/arm64/configs/vendor/minatok20.config`
- Modify: `repo/arch/arm64/configs/vendor/minatok20_susfs.config`

**Interfaces:**
- Consumes: `show_map_vma` in `fs/proc/task_mmu.c`, `map_files_get_link` in `fs/proc/base.c`
- Produces: `vendor/minatok20_stage3.config` fragment and `/proc/<pid>/maps` + `map_files` spoofing

- [ ] **Step 1: Apply `/proc/<pid>/maps` and `map_files` stealth (`69_hide_stuff`) in `fs/proc/task_mmu.c` and `fs/proc/base.c`**

In `fs/proc/task_mmu.c`:
- Add `show_vma_header_prefix_fake` (masks `VM_EXEC` as `'-'`).
- In `show_map_vma`, if `file && file->f_path.dentry`:
  - If `d_name.name` contains `"lineage"`, print header and set `name = "/system/framework/framework-res.apk"; goto done;`.
  - If `d_name.name` contains `"jit-zygote-cache"`, call `show_vma_header_prefix_fake` and jump to `bypass:` after normal `show_vma_header_prefix`.

In `fs/proc/base.c` (`map_files_get_link`):
- If `vma && vma->vm_file` and `vma->vm_file->f_path.dentry->d_name.name` contains `"lineage"`, resolve `kern_path("/system/framework/framework-res.apk", LOOKUP_FOLLOW, path)` instead of exposing the LineageOS apk symlink.

- [ ] **Step 2: Add Kryo 470 (`-mcpu=cortex-a76.cortex-a55`) tuning in `arch/arm64/Makefile` and create `minatok20_stage3.config`**

In `arch/arm64/Makefile`:
- Add `KBUILD_CFLAGS += $(call cc-option,-mcpu=cortex-a76.cortex-a55)`.

Create `arch/arm64/configs/vendor/minatok20_stage3.config`:
```ini
# Stage 3: SukiSU-Nova features + safe non-overclock debloat & scheduling tweaks
CONFIG_LOCALVERSION="-sukisu-nova"

# SukiSU-Nova extensions
CONFIG_KPM=y
CONFIG_KSU_FEATURE_ADBROOT=y

# Memory allocator & scheduler debug debloat (keeps FTRACE/AUDIT/KALLSYMS intact)
# CONFIG_SLUB_DEBUG is not set
# CONFIG_SCHED_DEBUG is not set
# CONFIG_QCOM_RTB is not set
# CONFIG_BLK_DEV_IO_TRACE is not set
# CONFIG_MSM_TZ_LOG is not set

# RCU priority boosting to prevent UI stalls under memory/IO pressure
CONFIG_RCU_BOOST=y
```

Update `arch/arm64/configs/vendor/minatok20_susfs.config`:
- Enable `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y`.

- [ ] **Step 3: Verify config fragments and procfs patches**

Run: `Get-Content repo/arch/arm64/configs/vendor/minatok20_stage3.config`
Expected: Contains `CONFIG_KPM=y`, `CONFIG_KSU_FEATURE_ADBROOT=y`, and debug debloat flags while keeping `FTRACE`, `AUDIT`, and `KALLSYMS` untouched.

---

### Task 4: Update Build Scripts, GitHub Actions Workflow & Documentation, Push & Trigger Cloud Build

**Files:**
- Modify: `repo/minatok20/build.sh`
- Modify: `repo/.github/workflows/build.yml`
- Modify: `repo/README.md`

**Interfaces:**
- Consumes: `https://github.com/SukiSU-Nova/SukiSU-Nova` (`builtin` branch), `vendor/minatok20_stage3.config`
- Produces: GitHub Actions workflow run producing flashable AnyKernel3 zip on `20032773/davinci-sukisu-nova-kernel`

- [ ] **Step 1: Update `minatok20/build.sh` and `.github/workflows/build.yml` for SukiSU-Nova (`builtin`)**

In `minatok20/build.sh`:
- Default `KSU_REF="${KSU_REF:-builtin}"`.
- Clone `https://github.com/SukiSU-Nova/SukiSU-Nova` (`--branch "$KSU_REF"`) into `KernelSU` and set up symlink/Kconfig via its `kernel/setup.sh`.
- Append `vendor/minatok20_stage3.config` to `DEFCONFIGS`.
- When `SUSFS=true`, enable `KSU_SUSFS`, `KPM`, `KSU_FEATURE_ADBROOT`, `KSU_SUSFS_PRIORITY_UID_FILTER`; when `SUSFS=false`, disable `KSU_SUSFS` (without referencing removed `KSU_MANUAL_HOOK`).

In `.github/workflows/build.yml`:
- Rename workflow to `Build SukiSU-Nova (davinci)`.
- Default `ksu_ref` input to `"builtin"`.
- Name output zip `sukisu-nova-davinci-${VARIANT}-$(date -u +%Y%m%d)-${SHORT_SHA}.zip`.

- [ ] **Step 2: Update `README.md` documenting SukiSU-Nova + SUSFS v2.4.0 + Stage 3 optimizations**

Update `README.md` to document SukiSU-Nova (`builtin` branch), SUSFS v2.4.0, KPM, ADB Root, `priority_uid_filter`, `/proc/maps` LineageOS hiding, Kryo 470 tuning, and Stage 3 debloat.

- [ ] **Step 3: Commit, push to `20032773/davinci-sukisu-nova-kernel`, and trigger GitHub Actions build**

Run:
```powershell
cd repo
git add -A
git commit -m "feat: integrate SukiSU-Nova (builtin) + SUSFS v2.4.0 + KPM + Stage 3 optimizations"
git remote set-url origin https://github.com/20032773/davinci-sukisu-nova-kernel.git
git push -u origin minatok20-susfs:main
gh workflow run build.yml --repo 20032773/davinci-sukisu-nova-kernel --ref main
```
Expected: Push succeeds to `20032773/davinci-sukisu-nova-kernel` (`main` branch) and GitHub Actions workflow starts building the kernel.
