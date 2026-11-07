# Official source baseline

The initial InfiltratorOS Kernel is the complete Ubuntu Linux HWE source
package **linux-hwe-7.0**, version **7.0.0-42.42~24.04.1**, from Ubuntu 24.04
(noble). It is the source identified by the Linux Mint 22.3 test system's
installed `linux-headers-7.0.0-42-generic`.

The entire applicable kernel source tree has been imported into the repository
root, preserving Kbuild, architecture code, drivers, kernel services,
documentation, Ubuntu distribution changes, licence files and copyright
attributions. APT/dpkg-source authenticated the package's published source
metadata and applied Ubuntu's source diff during the import.

The upstream kernel's `Makefile` identifies its underlying code as Linux
**7.0.14**; the distribution's installed ABI/package identity is
**7.0.0-42-generic**. These are different versioning systems. InfiltratorOS
compiles a separately named kernel using the distribution configuration;
it must not claim that a fresh Kbuild image is byte-for-byte identical to
Mint's signed distribution image.

Original Linux code retains its GPL-2.0-only and other applicable
licensing/attribution. First-party Infiltrator build tooling remains separate.
The upstream Kbuild Makefile has minimal InfiltratorOS build entry points.

This baseline has not yet passed a full native build on both Debian and
Linux Mint, boot verification or production hardware qualification. The
source import is not a binary release.

Official source package:
https://launchpad.net/ubuntu/+source/linux-hwe-7.0/7.0.0-42.42~24.04.1
