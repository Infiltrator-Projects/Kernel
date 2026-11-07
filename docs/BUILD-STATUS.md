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

**Current state (latest reported, 2026-11-07):** InfiltratorOS kernel native build passed certificate verification, generated a local signing key, linked the kernel objects, processed module metadata and reached Debian kernel packaging. The user's latest screenshot showed signing, stripping and building the image/debug packages. **The final shell exit and package inventory have not yet been supplied**, so neither a successful complete build nor installation/boot qualification can be asserted.

## Next immediate action — verify first packaging result, do not rebuild

The user reported the native kernel compilation advancing past `MODPOST` to
`SIGN`, `STRIP`, `INSTALL`, `DEPMOD`, and `dpkg-deb` creation of
`linux-image-7.0.14-infiltrator` and its debug-symbol package. This is
**observed progress**, not proof that every package finished successfully.

If the original compilation is still running, allow it to finish and **do not
start another build**. On the Mint laptop, check the saved log and any completed
packages without modifying source or build outputs:

```bash
cd ~/Kernel && printf '\n=== END OF BUILD LOG ===\n' && tail -n 35 "$HOME/Kernel-build-next.log" && printf '\n=== KERNEL PACKAGES ===\n' && find "$HOME" -maxdepth 3 -type f -name '*infiltrator*.deb' -printf '%p (%s bytes)\n' 2>/dev/null
```

The result needs to establish whether the builder printed
`Kernel: Created ... kernel .deb package(s) in dist/.` followed by a normal
shell prompt, and which .deb files actually exist. If the terminal is still
busy, the log is only provisional. If it failed, preserve the log and address
the **first real error** before rebuilding.

**Preservation:** Keep `~/Kernel/.config`, source-tree object files,
`~/Kernel/.native-build/`, `~/Kernel/dist/`, any generated .deb files in the
home directory, and `~/Kernel-build-next.log`. Never use `make clean`,
`mrproper`, `git clean` or delete these artifacts to fix a naming issue.
GitHub commits preserve source and decisions, not local compiled objects.

**Next engineering change once the baseline build is conclusively verified:**
separate product identity from implementation origin. InfiltratorOS Kernel
`VERSION=0.1.0` is its independent component version; the operating-system
integration package version is separate; the current Linux `7.0.14` and
`7.0.14-infiltrator` are historical source/transitional module ABI identifiers.
Rename the *actual Debian package metadata*, generated image/headers/debug
package family and visible release identity to InfiltratorOS only with matching
installer, module-loader, Boot and Setup changes. Do not relabel package
filenames alone or change the running kernel ABI while it is building.

Architectural destination: **InfiltratorOS as its own operating system and
kernel, developed from Linux source, with deliberate Linux application
compatibility**, analogous in evolutionary intent (not precise kernel origin)
to macOS being Unix-compatible but independently engineered. Retain original
source licences/provenance, and validate module compatibility separately.

## Longer-term goals (not yet completed)

- Finish and boot-qualify the first InfiltratorOS kernel baseline.
- Integrate the locally built kernel, drivers, filesystem modules and firmware in the existing `/System/Kernel` namespace through the **Boot** and future **Setup** component boundaries.
- Native target-machine hardware scan, configuration and individually compiled driver selection; preserve a tested recovery baseline.
- Carefully introduce the InfiltratorOS identity in product-facing paths and build tools without indiscriminately renaming compatibility-critical symbols, UAPI, Kbuild paths or inherited licence records.
- Treat success of GitHub syntax/contract checks as distinct from actual compilation, installation and runtime proof.
