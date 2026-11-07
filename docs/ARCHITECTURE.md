# Architecture

This repository starts with the Debian/Linux Mint Linux-kernel baseline while developing InfiltratorOS runtime ownership. Boot owns pre-kernel firmware responsibilities. Kernel owns post-boot memory, CPUs, interrupts, processes, scheduling, drivers, generic module discovery and runtime service interfaces. Individual Filesystem-* repositories continue to own all filesystem format logic. The kernel-side filesystem shared-object bridge is a design target, not implemented.

The initial source-first native builder obtains the exact installed kernel source, copies the running distribution configuration, retains normal Kbuild compiler flags and gives output a distinct Infiltrator name. It builds Debian image/headers packages without installing anything. APT/sudo is a temporary Mint/Debian host build dependency rather than a native InfiltratorOS runtime dependency. Source repositories require explicit host enablement.

Complete Ubuntu Linux HWE 7.0 kernel sources have now been imported directly into the repository root, preserving their original licence and attribution. The OS product is named InfiltratorOS; Linux-origin copyright, format conventions, internal identifiers and compatibility remain intact. The source package identity and exact Ubuntu version are recorded under docs/upstream/. This is currently a maintained Linux-derived kernel and not an independently implemented kernel.

Qualification still requires a clean Mint and Debian build, .deb checks, virtual-machine boot tests, physical tests, module-ABI tests, recovery and verified release publication. An imported source tree and a passing builder script check are not evidence of a successful kernel boot.
