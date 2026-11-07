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

16. **FIRST SUCCESSFUL FULL KERNEL PACKAGE BUILD — verified in the Mint terminal, 2026-11-07.** `make build-only SKIP_DEPS=1 JOBS=10` completed kernel linking, module signing and dependency generation, and the Debian package build chain (`dpkg-deb`, `dpkg-genbuildinfo`, `dpkg-genchanges`, `dpkg-source --after-build`). The terminal returned to its prompt following `Kernel: Created 3 kernel .deb package(s) in dist/. No kernel was installed.` The generated image was `linux-image-7.0.14-infiltrator_7.0.14-g8541848fe2d7-4_amd64.deb`; the debug package was also observed. The exact third package filename has not been supplied. The log is `~/Kernel-build-next.log` and packages are in `~/Kernel/dist/`. This proves build/package completion, not installation or boot.

17. **FIRST SUCCESSFUL NATIVE STAGING — verified by user terminal, 2026-11-07.** On the same Latitude 5550, after `git pull --ff-only`, `make stage-native` printed `Kernel stage: Unpacking locally compiled package: linux-image-7.0.14-infiltrator_7.0.14-g8541848fe2d7-4_amd64.deb`, `Kernel stage: Staged InfiltratorOS kernel 7.0.14-infiltrator under /home/ssmith/Kernel/dist/native/System/Kernel/`, then `Kernel stage: Not installed; no boot configuration, system files or running kernel were modified.` The shell returned normally. That proves **staging completed successfully** (the checksum-generation step is part of this stage). No boot, install or runtime compatibility test has yet occurred.

**Current state (confirmed 2026-11-07):** **Full native kernel build and InfiltratorOS /System/Kernel staging both SUCCEEDED on the actual Mint laptop**, with three compiled Debian packages in `dist/` and native tree under `dist/native/System/Kernel/`. The files are still a **transitional Linux-derived build** and carry inherited `linux-image` package names and `7.0.14` kernel ABI numbering. These are **not yet the intended product-facing package names or versions**; migrate independently of the preserved successful baseline. No installation or boot qualification has occurred.

18. **Native product package identities implemented and regression-tested in GitHub, 2026-11-07.** After the successful staging, the first-party `scripts/build-native.sh` now opts into a native mode in `scripts/package/mkdebian`. It generates *real Debian control and source metadata*, not renamed filenames: source package `infiltratoros-kernel`, package version `0.1.0-1`, image `infiltratoros-kernel-image-0.1.0`, headers `infiltratoros-kernel-headers-0.1.0`, and debug `infiltratoros-kernel-image-0.1.0-dbg`. `scripts/package/debian/rules` and `scripts/package/builddeb` recognise the native names. The existing exact kernel/module ABI `7.0.14-infiltrator` remains used for `/boot/vmlinuz-<ABI>`, modules, headers and module signing and is independently recorded in `X-InfiltratorOS-Module-ABI`. The native staging script now produces `InfiltratorOS-0.1.0.img`, `.config`, `.map`, keeps module ABI subdirectory and refuses to overwrite previous staging unless explicitly requested. Native staging defaults to `dist/native-0.1.0`, so the earlier `dist/native` baseline is preserved. A synthetic test exercises actual `mkdebian` generation, names, version and ABI metadata and protects upstream default mode; staging tests exercise old/new package selection, checksums and overwrite protection. GitHub Actions run `42356986972` **passed**. This is **source/contract test success**, not a second completed native Mint build of the new package names.

19. **LOCAL PACKAGE IDENTITY AND STAGING CONTRACT VERIFICATION PASSED — user-confirmed 2026-11-07.** On the original Dell Latitude 5550, `cd ~/Kernel && git pull --ff-only && make check` fast-forwarded `main` from `c8147a547` to `12e5fad5c`, and returned to the shell successfully. Output included `PASS: syntax and CLI-contract checks`, `PASS: certificate input handling preserves available keys and reports missing distro keys`, `PASS: native product version/ABI identity, legacy package fallback, checksums and preservation`, `PASS: native Debian image/headers/debug packages use component version, while transitional Linux ABI remains metadata`, and `PASS: real Kbuild string serialization, active/missing certificate paths, and inactive defaults`. The fake/native .deb names in the staging test came from temporary synthetic test fixtures, **not a fresh native kernel package build**. The corresponding GitHub Actions run `42357184247` also completed successfully.

**Current state (confirmed 2026-11-07):** The original full kernel build and `dist/native` staging **both succeeded** on the Mint laptop, and the subsequent **native InfiltratorOS product packaging contract checks passed both on the laptop and in GitHub CI**. The new `infiltratoros-kernel-image-0.1.0` binaries have **not yet been built**. No kernel installation or boot qualification has occurred. The architectural goal is an independent InfiltratorOS kernel with deliberate Linux compatibility.

20. **Architecture/staging gap confirmed 2026-11-07, during production of the newly branded binary packages.** The user rightly challenged the proposed directory tree: `stage-native.sh` copies the entire inherited Linux module layout under `dist/native-<VERSION>/System/Kernel/Modules/<linux-abi>/kernel/...`, although the InfiltratorOS OS filesystem specification calls for an independently owned single `.so` per filesystem under `/System/Filesystems/`, with `/System/Kernel/Filesystems/*.ko` only as transitional separately owned adapters. The generic kernel bridge required to consume a canonical `.so` is not yet implemented, and the broad copied distro module set is not the selected hardware-native module set. The newly named `infiltratoros-kernel-image-0.1.0` can be compiled and packaged correctly **without that implying a finished native kernel runtime or filesystem structure**. Refer to `docs/NATIVE-LAYOUT.md` for the explicit discrepancy. Do not try to fix module ABI/vermagic merely by renaming folders; do not delete existing compiled files. The current package build was observed reaching `dpkg-deb: building package 'infiltratoros-kernel-image-0.1.0'` in the latest screenshot, but has **not** been confirmed finished.

**Important limitation:** The current staging script should be described as a **Linux-compatible transitional artifact extractor**. It is **not** sufficient to declare the native InfiltratorOS module layout and filesystem-provider integration complete. Do not instruct the user to install/activate/boot from it.

21. **SECOND SUCCESSFUL FULL NATIVE KERNEL PACKAGE BUILD, 2026-11-07, observed on Shannon's Linux Mint Latitude 5550.** The user showed a complete terminal result from the second `make build-only SKIP_DEPS=1 JOBS=10`: `dpkg-deb` built `infiltratoros-kernel-image-0.1.0_0.1.0-1_amd64.deb` and `infiltratoros-kernel-image-0.1.0-dbg_0.1.0-1_amd64.deb`, completed `dpkg-genbuildinfo`, `dpkg-genchanges` and `dpkg-source --after-build`, then printed `Kernel: Created 3 InfiltratorOS Kernel 0.1.0 .deb package(s) in dist/. No kernel was installed.` and returned to `ssmith@ssmith-Latitude-5550:~/Kernel$`. This is **actual native kernel package-build success**, not merely a synthetic test. The third package is counted by the builder (normally headers), but its precise filename has not yet been independently read. Packages exist on the laptop under `~/Kernel/dist/`; the complete second build log is `~/Kernel-build-native-0.1.0.log`. The first successful Linux-named baseline and previously staged `~/Kernel/dist/native/` are also still on the laptop. No installation or boot test has occurred.

22. **Native directory/identity mismatch and source fix, 2026-11-07.** The user's established InfiltratorOS filesystem contract uses **capitalised full names**, with **uninstalled working data in `/Temporary/InfiltratorOS/`** and permanent activated kernel assets under **`/System/Kernel/`**. Earlier wrapper output `~/Kernel/dist/`, `.native-build/` and `dist/native-0.1.0/` did not follow that convention. The corrected source routes *new* build objects to `/Temporary/InfiltratorOS/Kernel/Build/`, uninstalled packages to `/Temporary/InfiltratorOS/Kernel/Packages/`, staged `System/Kernel` artifacts to `/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/`, and the self-extracting runner's logs to `/Temporary/InfiltratorOS/Kernel/Logs/`. The staging tree now uses `Modules/InfiltratorOS-0.1.0/` as a **presentation/storage directory**, while the **actual compiled module ABI and vermagic still equal `7.0.14-infiltrator`**. That inherited number comes from `Makefile` fields `VERSION=7 PATCHLEVEL=0 SUBLEVEL=14`, plus `LOCALVERSION=-infiltrator`. Changing the real module ABI needs a deliberate rebuild plus loader/Boot compatibility checks, not just renamed folders. The full source tree is still Linux-derived and this is not yet an independent, qualified runtime. **Crucially the current second build ran the old scripts and already finished successfully:** updating GitHub source does not retroactively relocate its binary outputs. Do **not** remove, rename, clean or overwrite any existing `~/Kernel/dist/`, `~/Kernel/.native-build/`, in-source compiled object files or logs. The new staging supports reading those earlier packages with `--packages "$PWD/dist"` without recompiling. GitHub preserves source and documentation, **not local binaries**. Latest GitHub layout regression check before recording this status (run `42359275973`) passed; a future actual Mint test of new staging paths is still pending.

**Confirmed state:** Two complete full native kernel package builds have succeeded on the Latitude 5550; first `linux-image`-named baseline was staged successfully, and the second generated **three genuine InfiltratorOS Kernel 0.1.0 packages** in `~/Kernel/dist/`. Native uninstalled Temporary layout source fixes and tests are committed, but the newly branded image has not yet been verified in its new staged `/Temporary/InfiltratorOS/Kernel/Staging/...` output. No actual host kernel installation or boot qualification has occurred.

## Historical recovery commands (already completed)

The commands to resolve permissions and stage the first native `0.1.0` build
**have now succeeded**. Do not repeat `make stage-native` or run
`--replace`: the uninstalled output is preserved under
`/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/`.
See the latest confirmed staging result and read-only checksum verification
below. Earlier failures are retained here as an audit trail, not open blockers.

## Latest host result — staged tree blocked by directory permissions

On 2026-11-07, Shannon ran `cd ~/Kernel && git pull --ff-only && make check && bash scripts/infiltrator/stage-native.sh --packages "$PWD/dist"` and updated to commit `3969b4eee`. All first-party tests passed, including native staging, package identity and certificate checks. Actual staging then reported `Kernel stage: Reading preserved legacy packages from /home/ssmith/Kernel/dist` followed by `mkdir: cannot create directory '/Temporary/InfiltratorOS/Kernel': Permission denied`, and returned to the prompt. **This is not a build or ABI failure. The three new `0.1.0` Debian packages in `~/Kernel/dist/` and previous successful build remain intact. The live `/System/Kernel` was never touched.** This attempt did not successfully create the new native staging tree.

To provide access without recursively chowning the shared InfiltratorOS Temporary root, provision **only** the Kernel child workspace:

```bash
sudo install -d -m 0750 -o "$(id -un)" -g "$(id -gn)" /Temporary/InfiltratorOS/Kernel
```

Then as the normal user, after updating Git, re-run **staging only**, not a full build:

```bash
cd ~/Kernel && git pull --ff-only && bash scripts/infiltrator/stage-native.sh --packages "$PWD/dist"
```

If access still fails, inspect `namei -l /Temporary/InfiltratorOS/Kernel` for parent traversal restrictions; do not change ownership of `/Temporary` or `/Temporary/InfiltratorOS` blindly. The staging script now reports targeted permissions guidance. Never run the entire build or staging as root merely to bypass this error, nor delete/clean any compiled artifacts.

## Latest host result — old native .deb omitted the optional ABI control field

On 2026-11-07, after successfully provisioning
`/Temporary/InfiltratorOS/Kernel` with
`sudo install -d -m 0750 -o "$(id -un)" -g "$(id -gn)" /Temporary/InfiltratorOS/Kernel`,
Shannon fast-forwarded to `9551cc86c` and tried
`bash scripts/infiltrator/stage-native.sh --packages "$PWD/dist"`.
This failed **before extracting or staging packages**, with:

```text
Kernel stage: ERROR: Native image package ABI () does not match built kernel (7.0.14-infiltrator)
```

**Verified root cause:** The second fully compiled InfiltratorOS Kernel 0.1.0
packages were generated with custom `X-InfiltratorOS-Module-ABI` and
`X-InfiltratorOS-Kernel-Version` fields in source `debian/control`.
`dpkg-gencontrol` does not copy plain custom `X-` fields to binary
package controls, so `dpkg-deb -f <package> X-InfiltratorOS-Module-ABI`
returns empty. The first synthetic test only inspected the source control,
not the generated binary .deb control; that was the test coverage gap.

**Source corrections committed:** Future packaging uses Debian's
`XB-X-InfiltratorOS-Module-ABI` and
`XB-X-InfiltratorOS-Kernel-Version` source fields, which
`dpkg-gencontrol` copies to binary package controls as
`X-InfiltratorOS-Module-ABI` and
`X-InfiltratorOS-Kernel-Version` (verified experimentally using the
real `dpkg-gencontrol`/`dpkg-deb` tools). The new test uses those real
tools and reads fields back from the resulting `.deb`.
**Existing already built binaries will not be edited or rebuilt merely
to add these optional metadata fields.** The staging script now tolerates
absent custom binary ABI metadata **only after validating an exact**
`/boot/vmlinuz-7.0.14-infiltrator` and
`/lib/modules/7.0.14-infiltrator/` **containing loadable .ko files** inside
the package. Explicit incorrect metadata still causes failure, as does a
missing/mismatched payload. ABI identity inside the actual modules remains
unchanged and is not renamed.

**Immediate safe action after the latest tests pass:**

```bash
cd ~/Kernel && git pull --ff-only && make check && bash scripts/infiltrator/stage-native.sh --packages "$PWD/dist"
```

Expected uninstalled staging under
`/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/System/Kernel/`,
**without installing a kernel, rebooting, cleaning, deleting, or altering
the preserved source/compiler output or successful package binaries.**
If the staging destination already exists, the script refuses to overwrite
it without explicit confirmation.

## Confirmed native 0.1.0 staging success on Latitude 5550 — 2026-11-07

After updating Git `main` to `151d83c6d`, Shannon successfully ran:

```bash
cd ~/Kernel && git pull --ff-only && make check && bash scripts/infiltrator/stage-native.sh --packages "$PWD/dist"
```

The local checks passed: syntax/CLI, certificate preparation, native Temporary
staging, existing ABI-field-less package fallback, actual `dpkg-gencontrol`
metadata generation, and effective Kbuild certificate configuration. Crucially,
the **real** staging step (not a synthetic test) reported:

```text
Kernel stage: Package lacks the optional binary ABI field; validating actual boot image and module payload before staging
Kernel stage: Unpacking locally compiled package: infiltratoros-kernel-image-0.1.0_0.1.0-1_amd64.deb
Kernel stage: Verified exact compiled image and module payload for ABI 7.0.14-infiltrator
Kernel stage: Staged InfiltratorOS Kernel 0.1.0 under /Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0/System/Kernel/
Kernel stage: The inherited module ABI remains in STAGING-STATUS.txt, not the native directory names
Kernel stage: Not installed; no boot configuration, system files or running kernel were modified.
```

The command returned to the normal shell prompt successfully. This **resolves
both** earlier blockers: inability to write the native Temporary workspace and
the missing custom ABI metadata in the historical already-built binary. The
latter was validated by inspecting the expected image path and module payload
instead of modifying or rebuilding the preserved package.

**Current confirmed milestone:** Two successful full kernel builds, a
successful Linux-compatible historical staging baseline, and **successful real
InfiltratorOS 0.1.0 package staging into the corrected Temporary/System/Kernel
artifact tree**. The historical `~/Kernel/dist/` packages, compilation
objects and both log files remain valuable and must not be cleaned or moved.
The staged tree is **uninstalled and still Linux ABI-derived**; there is no
proof of a working native loader, filesystem-engine bridge, hardware-selected
module set, Secure Boot, boot, or installed runtime.

**Next task is read-only integrity verification**, not another build or
staging operation:

```bash
stage=/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0
( cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt ) &&
printf 'Staged checksum verification: PASS\n' &&
cat "$stage/STAGING-STATUS.txt" &&
du -sh "$stage/System/Kernel/"*
```

The `sha256sum` validation checks the content manifest generated by staging,
but is separate from actual kernel installation/boot qualification. Further
work should proceed bottom-up to reconcile module ABI identity, loader and Boot
handoff, not by renaming internal Linux symbols in the already-built package.

## Verified staged artifact integrity — Latitude 5550, 2026-11-07

After the successful first native `0.1.0` staging, Shannon ran the following
**read-only** verification against the actual on-disk artifacts:

```bash
stage=/Temporary/InfiltratorOS/Kernel/Staging/InfiltratorOS-0.1.0
( cd "$stage" && sha256sum --quiet -c SHA256SUMS.txt ) &&
echo "Staged checksum verification: PASS" &&
cat "$stage/STAGING-STATUS.txt" &&
du -sh "$stage/System/Kernel/"*
```

It completed successfully and printed `Staged checksum verification: PASS`.
The `STAGING-STATUS.txt` evidence identifies
`product=InfiltratorOS Kernel`, `product_version=0.1.0`,
`kernel_release=7.0.14-infiltrator`,
`transitional_module_abi=7.0.14-infiltrator`,
`module_namespace=System/Kernel/Modules/InfiltratorOS-0.1.0`,
`staging_location=Temporary`,
`runtime_status=transitional-not-bootable`,
`source_image_package=infiltratoros-kernel-image-0.1.0_0.1.0-1_amd64.deb`,
and `boot_install=not-performed`, `host_install=not-performed`,
`secure_boot=not-qualified`,
`module_runtime_path=not-integrated`, and
`filesystem_provider_modules=not-included`.

On-disk `du -sh` output: `Images=26M`, `Modules=645M`,
`Filesystems=4.0K`, `Firmware=4.0K`. The latter two are
**empty, intentionally reserved directories**; their existence does not
mean filesystem providers or firmware were installed. The module tree
contains the currently broad Linux-compatible module set, not yet a
hardware-qualified, minimal native driver set.

**Milestone closed:** InfiltratorOS Kernel `0.1.0` compiled, packaged,
uninstalled-native-staged and checksum-verified on the actual laptop.
This verification proves **staged artifact integrity**, not ELF/EFI-stub
bootability, initramfs or filesystem-root handoff, runtime module loading,
Secure Boot, firmware qualification or successful boot.

**Next integration boundary, evaluated from Boot repository:** Boot
already owns the firmware-stage handoff and contains an existing OVMF
Linux EFI-stub + initramfs test harness
(`Infiltrator-Projects/Boot/tests/test_so_boot.py`) and separate physical
Dell boot evidence in `Boot/docs/VALIDATION.md`. Those results apply to
the kernel/images specifically tested there; they **do not qualify this new
InfiltratorOS Kernel `0.1.0` image**. The next bottom-up integration task
is a controlled, non-installed QEMU/OVMF handoff test using the exact
checksum-verified staged image plus a compatible test initramfs, with explicit
proof of an initramfs marker and preserved current host boot. Before such a
test, verify the staged kernel configuration enables the necessary x86 EFI
stub and initramfs support. Do not deploy or boot the compiled kernel on
the physical host as a shortcut.

## Longer-term goals (not yet completed)

- Finish and boot-qualify the first InfiltratorOS kernel baseline.
- Integrate the locally built kernel, drivers, filesystem modules and firmware in the existing `/System/Kernel` namespace through the **Boot** and future **Setup** component boundaries.
- Native target-machine hardware scan, configuration and individually compiled driver selection; preserve a tested recovery baseline.
- Carefully introduce the InfiltratorOS identity in product-facing paths and build tools without indiscriminately renaming compatibility-critical symbols, UAPI, Kbuild paths or inherited licence records.
- Treat success of GitHub syntax/contract checks as distinct from actual compilation, installation and runtime proof.
