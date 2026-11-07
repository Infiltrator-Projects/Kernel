# Architecture

This repository starts with the Debian/Linux Mint Linux-kernel baseline while developing InfiltratorOS runtime ownership. Boot owns pre-kernel firmware responsibilities. Kernel owns post-boot memory, CPUs, interrupts, processes, scheduling, drivers, generic module discovery and runtime service interfaces. Individual Filesystem-* repositories continue to own all filesystem format logic. The kernel-side filesystem shared-object bridge is a design target, not implemented.

The initial source-first native builder obtains the exact installed kernel source, copies the running distribution configuration, retains normal Kbuild compiler flags and gives output a distinct Infiltrator name. It builds Debian image/headers packages without installing anything. APT/sudo is a temporary Mint/Debian host build dependency rather than a native InfiltratorOS runtime dependency. Source repositories require explicit host enablement.

Full imported kernel sources will be tracked under src/linux, with upstream licence/attribution and an accurate source provenance statement. Until then this repository contains only the build infrastructure and must not be described as a completed kernel fork.

Qualification still requires full Linux source import, a clean Mint and Debian build, .deb checks, virtual-machine boot tests, physical tests, module-ABI tests, recovery and verified release publication.
