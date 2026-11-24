# Engineering Philosophy

Kernel adopts the [Infiltrator Engineering Philosophy](https://github.com/Infiltrator-Projects/Libraries/blob/main/docs/PHILOSOPHY.md) as its governing standard. These requirements define the target and its acceptance boundaries, not a claim that migration is complete.

## Architecture and ownership

The Kernel owns privileged resource management, scheduling, memory, hardware interfaces and generic integration with filesystem modules. Independent providers own format semantics; Common owns the [V2 filesystem ABI](https://github.com/Infiltrator-Projects/Libraries/blob/main/docs/FILESYSTEM_COMMON_ABI_V2.md). The intended filesystem execution path uses only V2 modules, with a qualified generic kernel integration layer, never FUSE. Preserve a working independent recovery kernel until boot, root mounting and filesystem lifecycle qualification demonstrates the replacement is safe.

## Integrity and qualification

Document execution context, memory ownership, concurrency, privilege and I/O boundaries, loader validation and failure/recovery semantics. Validate reproducible configuration and exact source and dependency identities. Qualify module loading, boot, storage, interruption and upgrade/recovery in disposable environments before promotion. Do not classify a successful build or a hosted filesystem test as proof of a bootable kernel.

## Craft and release

Preserve upstream attribution and licensing. Record first-party changes and postgraduate-level technical reasoning, including rejected alternatives and known gaps. Publish artifacts with explicit qualification and immutable identities; retain the distinction between experimental and qualified releases.
