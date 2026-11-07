# Kernel

InfiltratorOS kernel project.

**Current state:** Native Linux-kernel baseline, not yet a standalone operating-system kernel. The complete Linux source has NOT yet been committed to this repository.

The initial builder supports **Debian and Linux Mint** using the running kernel's configuration and the exact kernel source package identified by its installed headers. It compiles locally with distribution defaults, creates separately named Debian packages, and never installs a kernel or changes a boot entry.

## Commands

    git pull --ff-only
    make probe
    make configure-only
    make build-only

For an already extracted source tree:

    bash scripts/build-native.sh --build-only --source-dir upstream/linux-hwe-7.0-7.0.0 --skip-deps

The builder installs source-package build dependencies using APT/sudo unless --skip-deps is requested. Source repositories (deb-src) must be enabled on the host; the builder never silently edits repository policy. Offline or native-InfiltratorOS builds will require a separate toolchain/provisioning contract.

Kernel source belongs in src/linux/ when formally imported into Git, preserving original licence and history/provenance. Downloads in upstream/, builds in .native-build/ and packages in dist/ are local and excluded from Git.

## Ownership

Boot owns firmware selection and kernel handoff. Kernel owns CPU, memory, scheduling, processes and runtime generic module loading. Independent Filesystem-* repositories own their filesystem engines; InfiltratorOS owns OS integration. Linux kernel source licensing/attribution must be preserved. Build tooling has GPL-3.0-or-later headers.

**Not yet qualified:** a full successful kernel compilation, Debian/Mint hardware boot, native filesystem .so kernel bridge, installation/recovery, or complete upstream Linux source import. A script passing syntax tests does not prove these milestones.
