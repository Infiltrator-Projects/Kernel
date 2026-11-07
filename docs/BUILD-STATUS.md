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
7. The first stricter preflight test on the Mint laptop reported `Kernel: ERROR: missing generated auto.conf; regenerate config before compiling`. This was a **build-script ordering error**: the script invoked `syncconfig` directly before requiring an output which had not been generated. The user did **not** reach another full compilation or installation.
8. The builder now uses the real Kbuild `prepare` target, which materialises generated configuration and headers, **then** compares `.config` against `include/config/auto.conf` and checks for missing vendor certificate files before proceeding. A new GitHub Actions job compiled actual configuration/preparation tools in an isolated out-of-tree build and passed on 2026-11-07. This validates the preparation sequence on the CI host, not yet a complete Linux Mint compilation or boot.
9. On the next actual Mint run, `make configure-only SKIP_DEPS=1` **still failed** with `Kernel: ERROR: missing generated auto.conf` even though Kbuild's `prepare` target itself did work. Source inspection established the cause: the top-level `make configure-only` / `make build-only` exports Kbuild's internal `sub_make_done=1`; the nested kernel makes inherited it and therefore skipped the outer pass that honours `O=`. Build work had actually been occurring **in the source directory** rather than the expected `.native-build/obj`. This also explains the earlier missing Canonical PEM file at compilation.
10. Added `scripts/infiltrator/run-kbuild.sh` to reset `sub_make_done` on every independent kernel make. The regression test reproduces `sub_make_done=1` and performs real `olddefconfig`/`prepare` operations in a temporary `O=` directory. **This test passed on GitHub Actions**. The corrected wrapper has not yet been run on the Mint laptop.
11. Rather than deleting hours of previously compiled objects, the builder now detects a legacy in-source build by the presence of its `.config` and `include/config/auto.conf`. It reuses that build in place until the first baseline is qualified. On a clean checkout it uses the intended out-of-tree `.native-build/obj`. After a successful build, `.native-build/last-completed-objtree` records the actual object directory for native artifact staging. The compiled objects are local, **not** stored in GitHub. Do not run `mrproper`, `clean`, or `git clean` to try to correct the build.

**Current state:** Native Mint source was imported and configured but a complete build is still outstanding. The updated wrapper and legacy-object reuse require verification on the actual Mint host.

## Next immediate action

First confirm the updated prepare step works on the original Mint host **without beginning the full kernel build**:

```bash
cd ~/Kernel && git pull --ff-only && make configure-only SKIP_DEPS=1
```

Success requires `Kernel: Effective compilation certificate settings verified (no missing distro PEMs).` followed by `Kernel: Configured at ...`. On this laptop the configured object tree may be **`~/Kernel/.config`**, because the earlier bug caused a real in-source build; the builder should explicitly report that it is reusing those existing compiled objects.

**Only after that succeeds**, continue the incremental compilation with a full diagnostic log:

```bash
cd ~/Kernel && set -o pipefail && make build-only SKIP_DEPS=1 JOBS=10 2>&1 | tee "$HOME/Kernel-build-next.log"
```

A preflight failure is a blocker, not a reason to run another long compile. Compare `.native-build/obj/.config` and `.native-build/obj/include/config/auto.conf` if the generated values still diverge.

Do **not** run `make clean`, `mrproper`, delete `.native-build/`, reset the repository, or remove the logs. The existing parallel-build objects can generally be reused.

The old diagnostic file, if present, is `~/Kernel-build.log`. The new log is `~/Kernel-build-next.log`. Neither should be committed into Git: they can be large and machine-specific.

## Longer-term goals (not yet completed)

- Finish and boot-qualify the first InfiltratorOS kernel baseline.
- Integrate the locally built kernel, drivers, filesystem modules and firmware in the existing `/System/Kernel` namespace through the **Boot** and future **Setup** component boundaries.
- Native target-machine hardware scan, configuration and individually compiled driver selection; preserve a tested recovery baseline.
- Carefully introduce the InfiltratorOS identity in product-facing paths and build tools without indiscriminately renaming compatibility-critical symbols, UAPI, Kbuild paths or inherited licence records.
- Treat success of GitHub syntax/contract checks as distinct from actual compilation, installation and runtime proof.
