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

12. On the latest actual Mint test, Kbuild correctly reused the in-source objects and generated `SYNC include/config/auto.conf.cmd`, but the new certificate verifier rejected `MODULE_SIG_KEY`: `.config=certs/signing_key.pem`, `auto.conf=''`. The verification code erroneously required every saved config string to appear in `auto.conf`. **Kconfig deliberately omits inactive options from its generated build configuration**; this absence is expected when `MODULE_SIG` and `IMA_APPRAISE_MODSIG` are off. The verifier now checks Kconfig dependency activation for trusted, revoked and module-signing keys, skips genuinely inactive settings, and still rejects stale or missing active certificate references. Added synthetic active/inactive regressions and a real in-source GitHub Actions configuration test. Recheck the current CI result before claiming success. No kernel install or boot test has occurred.

13. The latest Mint `make configure-only SKIP_DEPS=1` again reached Kbuild `prepare` but was rejected by the certificate verifier: `.config=certs/signing_key.pem, auto.conf=''`. The verifier only recognised *quoted* strings even though the Linux Kconfig source `scripts/kconfig/confdata.c` deliberately writes `.config` with `escape_string=true` (quoted) and `include/config/auto.conf` with `escape_string=false` (unquoted). It was parsing the real auto.conf path as an empty string. This is the **verified root cause** of the latest false-positive.
14. Updated the verifier to read and normalise both formats without evaluating either string and to ignore dependencies that are inactive. Replaced the fixture tests with authentic quoted and unquoted formats, plus active/missing key checks. Added a real Kbuild CI check with `CONFIG_MODULE_SIG=y` to validate the serialization. GitHub Actions run 42353220035 **passed**, including real Kbuild with module signing enabled and an assertion that `.config` uses quoted strings while `include/config/auto.conf` uses unquoted strings. The next actual Mint configuration run remains to be checked; the previous entire kernel build is still **not** completed.

15. **Verified on the actual Mint test laptop:** after Git fast-forward to `8541848fe`, the user ran `bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$PWD" "$PWD/.config"` in `~/Kernel`; it returned `Kernel: Effective compilation certificate settings verified (no missing distro PEMs).` with exit success. This confirms the certificate preflight against the generated in-source configuration on that machine. **It is not evidence that the complete kernel compiled, packaged or booted.** The next step is to resume the incremental native package build with full logging: `set -o pipefail && make build-only SKIP_DEPS=1 JOBS=10 2>&1 | tee "$HOME/Kernel-build-next.log"`. Preserve the existing in-source object files and do not run any clean target.

16. **FIRST SUCCESSFUL NATIVE COMPILE AND PACKAGE — verified by user terminal, 2026-11-07.** On Dell Latitude 5550 with Linux Mint 22.3, `make build-only SKIP_DEPS=1 JOBS=10` finished after the certificate fix, reaching kernel/link, signed modules, `DEPMOD`, and the complete Debian packaging chain (`dpkg-deb`, `dpkg-genbuildinfo`, `dpkg-genchanges`, `dpkg-source --after-build`). The terminal showed `Kernel: Created 3 kernel .deb package(s) in dist/. No kernel was installed.` and returned to `ssmith@ssmith-Latitude-5550:~/Kernel# InfiltratorOS Kernel — build and development handoff

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

12. On the latest actual Mint test, Kbuild correctly reused the in-source objects and generated `SYNC include/config/auto.conf.cmd`, but the new certificate verifier rejected `MODULE_SIG_KEY`: `.config=certs/signing_key.pem`, `auto.conf=''`. The verification code erroneously required every saved config string to appear in `auto.conf`. **Kconfig deliberately omits inactive options from its generated build configuration**; this absence is expected when `MODULE_SIG` and `IMA_APPRAISE_MODSIG` are off. The verifier now checks Kconfig dependency activation for trusted, revoked and module-signing keys, skips genuinely inactive settings, and still rejects stale or missing active certificate references. Added synthetic active/inactive regressions and a real in-source GitHub Actions configuration test. Recheck the current CI result before claiming success. No kernel install or boot test has occurred.

13. The latest Mint `make configure-only SKIP_DEPS=1` again reached Kbuild `prepare` but was rejected by the certificate verifier: `.config=certs/signing_key.pem, auto.conf=''`. The verifier only recognised *quoted* strings even though the Linux Kconfig source `scripts/kconfig/confdata.c` deliberately writes `.config` with `escape_string=true` (quoted) and `include/config/auto.conf` with `escape_string=false` (unquoted). It was parsing the real auto.conf path as an empty string. This is the **verified root cause** of the latest false-positive.
14. Updated the verifier to read and normalise both formats without evaluating either string and to ignore dependencies that are inactive. Replaced the fixture tests with authentic quoted and unquoted formats, plus active/missing key checks. Added a real Kbuild CI check with `CONFIG_MODULE_SIG=y` to validate the serialization. GitHub Actions run 42353220035 **passed**, including real Kbuild with module signing enabled and an assertion that `.config` uses quoted strings while `include/config/auto.conf` uses unquoted strings. The next actual Mint configuration run remains to be checked; the previous entire kernel build is still **not** completed.

15. **Verified on the actual Mint test laptop:** after Git fast-forward to `8541848fe`, the user ran `bash scripts/infiltrator/verify-certificate-config.sh "$PWD" "$PWD" "$PWD/.config"` in `~/Kernel`; it returned `Kernel: Effective compilation certificate settings verified (no missing distro PEMs).` with exit success. This confirms the certificate preflight against the generated in-source configuration on that machine. **It is not evidence that the complete kernel compiled, packaged or booted.** The next step is to resume the incremental native package build with full logging: `set -o pipefail && make build-only SKIP_DEPS=1 JOBS=10 2>&1 | tee "$HOME/Kernel-build-next.log"`. Preserve the existing in-source object files and do not run any clean target.

. The output names shown include `linux-image-7.0.14-infiltrator_7.0.14-g8541848fe2d7-4_amd64.deb` and the corresponding `linux-image-7.0.14-infiltrator-dbg` package. The builder counted a third matching package, expected to be headers, but its exact filename has not yet been reported. The local build log is `~/Kernel-build-next.log`; the packages were copied to `~/Kernel/dist/`. No kernel installation, activation, boot test, or native stage verification has occurred.

**Current state (confirmed 2026-11-07):** First native kernel build **SUCCEEDED** and created three Debian kernel packages in `dist/`, without installing or booting. Next milestone: **stage the verified compiled image and modules in the InfiltratorOS native `/System/Kernel` artifact tree** (under `dist/native` only). This is a functional compilation baseline, not a qualified independent kernel release.

## Next immediate action — stage successful build without installing

On the Mint laptop, the completed kernel source and object tree are still
local; the source Git repository preserves the build logic and this record,
but **not** the compiled output or host log.

The next step is `make stage-native` on the **existing** compiled package
set. It uses `.native-build/last-completed-objtree` to find the in-source
objects, and unpacks the local image .deb into
`dist/native/System/Kernel/{Images,Modules,Filesystems,Firmware}`. It also
writes integrity checksums and a staging-status record. This does not install
anything to `/System`, `/boot`, or the running kernel.

To avoid overwriting any previously staged output, run:

```bash
cd ~/Kernel && git pull --ff-only && if [[ -e dist/native || -L dist/native ]]; then echo "Existing dist/native found — preserving it; no staging performed"; else make stage-native; fi
```

Expected: `Kernel stage: Staged InfiltratorOS kernel 7.0.14-infiltrator under .../dist/native/System/Kernel/`,
followed by `Not installed; no boot configuration, system files or running
kernel were modified.` If staging reports a missing image/objects, **do not
rebuild or clean**; inspect the staging result and the existing `dist/`
packages.

**Preservation:** Keep `~/Kernel/.config`, source-tree compiler objects,
`~/Kernel/.native-build/`, `~/Kernel/dist/`, all generated .deb files,
and `~/Kernel-build-next.log`. Never run `make clean`, `mrproper`,
`git clean`, delete the kernel directory, or reinstall the host as part
of this transition.

**After staging is verified:** migrate user-visible package identity and
component version from inherited `linux-image-7.0.14-infiltrator` /
`7.0.14` to InfiltratorOS Kernel `0.1.0` in the *actual package
generator and metadata*, including image/headers/debug dependencies,
version sources and native installer contract. Preserve transitional kernel
ABI and Linux compatibility during migration; do not merely rename files.
The long-term kernel is an independent InfiltratorOS architecture developed
from the Linux source foundation, with deliberate Linux compatibility,
not a permanently rebranded Linux distro.

## Longer-term goals (not yet completed)

- Finish and boot-qualify the first InfiltratorOS kernel baseline.
- Integrate the locally built kernel, drivers, filesystem modules and firmware in the existing `/System/Kernel` namespace through the **Boot** and future **Setup** component boundaries.
- Native target-machine hardware scan, configuration and individually compiled driver selection; preserve a tested recovery baseline.
- Carefully introduce the InfiltratorOS identity in product-facing paths and build tools without indiscriminately renaming compatibility-critical symbols, UAPI, Kbuild paths or inherited licence records.
- Treat success of GitHub syntax/contract checks as distinct from actual compilation, installation and runtime proof.
