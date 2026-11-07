# InfiltratorOS Kernel — build and development handoff

Last updated: 2026-11-07 (Australia/Melbourne). This file is a **persistent factual status record**, not a completed-release declaration.

## Source and project identity

- GitHub: [Infiltrator-Projects/Kernel](https://github.com/Infiltrator-Projects/Kernel), single active `main` branch.
- Official Ubuntu HWE source package: `linux-hwe-7.0=7.0.0-42.42~24.04.1`, imported at the **root** of this Git repository.
- Source `Makefile`: `7.0.14`; original Linux Mint 22.3 host ABI: `7.0.0-42-generic`.
- Test machine: Dell Latitude 5550, Linux Mint 22.3, x86_64.
- Configured custom kernel release: `7.0.14-infiltrator`.
- Retain Linux/Ubuntu-origin licence notices and compatible internal identifiers while progressively building InfiltratorOS as a distinct operating-system product.
- Planned native installation structure is `/System/Kernel/{Images,Modules,Filesystems,Firmware}`; source lives in the repository root. The native `.run` builder and staging scripts exist, but **no new kernel has been installed or boot-tested**.

## Verified on the test laptop

1. Exact official Ubuntu HWE source installed into the repo; successful push and fast-forward local Git pulls.
2. Installed all relevant APT source build dependencies.
3. `make configure-only SKIP_DEPS=1` succeeded with Mint's running kernel config.
4. `make check` and GitHub's script/contract checks have passed.
5. A full native build with `make build-only SKIP_DEPS=1 JOBS=10` compiled many modules, but **did not finish**. The original cause, seen in both independent build attempts, was:

   ```text
   make[7]: *** No rule to make target 'debian/canonical-certs.pem', needed by 'certs/x509_certificate_list'. Stop.
   ```

6. The first fix modified only `.native-build/obj/.config`, removing unavailable Canonical trusted and revoked certificate paths. However the second build still tried to load the old certificate path. The most likely reason is that generated `include/config/auto.conf` had retained old values, or that package-build recursion used them. This diagnosis must be proven by the next verification step.
7. The native build script now explicitly runs `syncconfig` and **checks the effective compiled settings in both** `.config` and `include/config/auto.conf` before beginning the kernel package build. Regression tests reject stale Canonical certificate references.
8. All previous compiler outputs are expected to remain in the local untracked `.native-build/obj/` tree; there is no instruction to clean or remove them. GitHub contains the source and the fixes, **not** the already-built object files from the user's laptop.

## Next immediate action

Run from the existing test computer:

```bash
cd ~/Kernel && git pull --ff-only && make check
```

Then re-attempt the native compilation **with full diagnostic logging**:

```bash
cd ~/Kernel && set -o pipefail && make build-only SKIP_DEPS=1 JOBS=10 2>&1 | tee "$HOME/Kernel-build-next.log"
```

The builder must display a successful effective certificate check **before** it starts compiling. If it instead exits at the check, inspect the actual `.native-build/obj/.config` and `.native-build/obj/include/config/auto.conf`, rather than wasting hours compiling the same known-broken config.

Do **not** run `make clean`, `mrproper`, delete `.native-build/`, reset the repository, or remove the logs. The existing parallel-build objects can generally be reused.

The old diagnostic file, if present, is `~/Kernel-build.log`. The new log is `~/Kernel-build-next.log`. Neither should be committed into Git: they can be large and machine-specific.

## Longer-term goals (not yet completed)

- Finish and boot-qualify the first InfiltratorOS kernel baseline.
- Integrate the locally built kernel, drivers, filesystem modules and firmware in the existing `/System/Kernel` namespace through the **Boot** and future **Setup** component boundaries.
- Native target-machine hardware scan, configuration and individually compiled driver selection; preserve a tested recovery baseline.
- Carefully introduce the InfiltratorOS identity in product-facing paths and build tools without indiscriminately renaming compatibility-critical symbols, UAPI, Kbuild paths or inherited licence records.
- Treat success of GitHub syntax/contract checks as distinct from actual compilation, installation and runtime proof.
