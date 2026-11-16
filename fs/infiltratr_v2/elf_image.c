// SPDX-License-Identifier: GPL-2.0-only
/*
 * InfiltratorOS Kernel's bounded, non-executing Common V2 image parser.
 *
 * A hosted .so is a signed CARRIER, not executable kernel code. Only its
 * .infiltrator_boot section can contain a freestanding no-import image.
 * This parser rejects dynamic imports, malformed ranges, executable data,
 * constructors and any relocation other than absolute-base RELATIVE.
 * No format-specific filesystem implementation appears here.
 */
#include <linux/elf.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/string.h>
#include "elf_image.h"

/* Stable ELF64 ABI values absent from some kernel UAPI header revisions.
 * These are format-neutral executable-linkage tags, not filesystem code. */
#ifndef SHT_RELR
#define SHT_RELR 19
#endif
#ifndef DT_BIND_NOW
#define DT_BIND_NOW 24
#endif
#ifndef DT_INIT_ARRAY
#define DT_INIT_ARRAY 25
#endif
#ifndef DT_FINI_ARRAY
#define DT_FINI_ARRAY 26
#endif
#ifndef DT_RUNPATH
#define DT_RUNPATH 29
#endif
#ifndef DT_PREINIT_ARRAY
#define DT_PREINIT_ARRAY 32
#endif

#define IFS_V2_MAX_SECTIONS 256u
#define IFS_V2_MAX_PHDRS 32u
#define IFS_V2_MAX_SYMS 4096u
#define IFS_V2_MAX_RELOCS 65536u
#define IFS_V2_PAGESIZE 4096ULL
#define IFS_V2_EXPORT "infiltrator_filesystem_api_v2"

static bool span(u64 offset, u64 count, u64 total)
{
    return offset <= total && count <= total - offset;
}

static bool elf_header(const u8 *raw, size_t bytes, Elf64_Ehdr *elf)
{
    if (bytes < sizeof(*elf))
        return false;
    memcpy(elf, raw, sizeof(*elf));
    return memcmp(elf->e_ident, ELFMAG, SELFMAG) == 0 &&
        elf->e_ident[EI_CLASS] == ELFCLASS64 &&
        elf->e_ident[EI_DATA] == ELFDATA2LSB &&
        elf->e_ident[EI_VERSION] == EV_CURRENT &&
        elf->e_type == ET_DYN && elf->e_machine == EM_X86_64 &&
        elf->e_version == EV_CURRENT && !elf->e_entry &&
        elf->e_ehsize == sizeof(*elf) &&
        elf->e_shentsize == sizeof(Elf64_Shdr) &&
        elf->e_phentsize == sizeof(Elf64_Phdr) &&
        elf->e_shnum && elf->e_shnum <= IFS_V2_MAX_SECTIONS &&
        elf->e_phnum && elf->e_phnum <= IFS_V2_MAX_PHDRS &&
        elf->e_shstrndx < elf->e_shnum &&
        span(elf->e_shoff, (u64)elf->e_shnum * sizeof(Elf64_Shdr), bytes) &&
        span(elf->e_phoff, (u64)elf->e_phnum * sizeof(Elf64_Phdr), bytes);
}

static void section(const u8 *raw, const Elf64_Ehdr *elf,
                    unsigned int i, Elf64_Shdr *sh)
{
    memcpy(sh, raw + elf->e_shoff + i * sizeof(*sh), sizeof(*sh));
}

static void program(const u8 *raw, const Elf64_Ehdr *elf,
                    unsigned int i, Elf64_Phdr *ph)
{
    memcpy(ph, raw + elf->e_phoff + i * sizeof(*ph), sizeof(*ph));
}

static bool section_name(const u8 *raw, size_t bytes, Elf64_Shdr strings,
                         const Elf64_Shdr *sh, const char *name)
{
    const char *s;
    size_t remain;
    if (strings.sh_type != SHT_STRTAB ||
        !span(strings.sh_offset, strings.sh_size, bytes) ||
        sh->sh_name >= strings.sh_size)
        return false;
    s = (const char *)raw + strings.sh_offset + sh->sh_name;
    remain = strings.sh_size - sh->sh_name;
    return strnlen(s, remain) < remain && !strcmp(s, name);
}

static bool exact_dynsym(const u8 *raw, size_t bytes,
                         const Elf64_Ehdr *elf)
{
    Elf64_Shdr symbols = {}, strings;
    unsigned int matches = 0;
    unsigned int i, j;
    bool found = false;

    for (i = 1; i < elf->e_shnum; ++i) {
        Elf64_Shdr sh;
        section(raw, elf, i, &sh);
        if (sh.sh_type == SHT_DYNSYM) {
            if (found || !sh.sh_size ||
                sh.sh_entsize != sizeof(Elf64_Sym) ||
                sh.sh_size % sizeof(Elf64_Sym) ||
                sh.sh_size > IFS_V2_MAX_SYMS * sizeof(Elf64_Sym) ||
                !span(sh.sh_offset, sh.sh_size, bytes) ||
                sh.sh_link >= elf->e_shnum)
                return false;
            symbols = sh;
            found = true;
        }
    }
    if (!found)
        return false;
    section(raw, elf, symbols.sh_link, &strings);
    if (strings.sh_type != SHT_STRTAB ||
        !span(strings.sh_offset, strings.sh_size, bytes))
        return false;
    for (j = 1; j < symbols.sh_size / sizeof(Elf64_Sym); ++j) {
        Elf64_Sym symbol;
        const char *name;
        size_t available;
        memcpy(&symbol, raw + symbols.sh_offset + j * sizeof(symbol),
               sizeof(symbol));
        if (symbol.st_name >= strings.sh_size)
            return false;
        name = (const char *)raw + strings.sh_offset + symbol.st_name;
        available = strings.sh_size - symbol.st_name;
        if (strnlen(name, available) == available)
            return false;
        if (strcmp(name, IFS_V2_EXPORT))
            continue;
        if (symbol.st_shndx == SHN_UNDEF ||
            ELF64_ST_TYPE(symbol.st_info) != STT_FUNC ||
            ELF64_ST_BIND(symbol.st_info) != STB_GLOBAL ||
            !symbol.st_size)
            return false;
        ++matches;
    }
    return matches == 1;
}

static bool carrier_identity(const u8 *raw, const Elf64_Shdr *sh,
                             const char *format)
{
    char identity[96];
    int n = scnprintf(identity, sizeof(identity), "IFS-MODULE:%s:common2",
                      format);
    if (!n || n >= sizeof(identity) || sh->sh_size < n + 1)
        return false;
    return memchr(raw + sh->sh_offset, '\0', sh->sh_size) &&
        !memcmp(raw + sh->sh_offset, identity, n + 1);
}

static int extract_carrier(const u8 *raw, size_t bytes,
                           const char *format, const u8 **inner,
                           size_t *inner_size)
{
    Elf64_Ehdr elf;
    Elf64_Shdr names;
    Elf64_Shdr payload = {}, marker = {};
    unsigned int i;
    bool got_payload = false, got_marker = false;

    if (!elf_header(raw, bytes, &elf))
        return -ENOEXEC;
    section(raw, &elf, elf.e_shstrndx, &names);
    if (names.sh_type != SHT_STRTAB ||
        !span(names.sh_offset, names.sh_size, bytes))
        return -ENOEXEC;
    if (!exact_dynsym(raw, bytes, &elf))
        return -ENOEXEC;
    for (i = 1; i < elf.e_shnum; ++i) {
        Elf64_Shdr sh;
        section(raw, &elf, i, &sh);
        if (sh.sh_type != SHT_NOBITS &&
            !span(sh.sh_offset, sh.sh_size, bytes))
            return -ENOEXEC;
        if (section_name(raw, bytes, names, &sh, ".infiltrator_boot")) {
            if (got_payload || sh.sh_type != SHT_PROGBITS ||
                sh.sh_flags || sh.sh_addr || sh.sh_link || sh.sh_info ||
                sh.sh_entsize || sh.sh_size < sizeof(Elf64_Ehdr) ||
                sh.sh_size > IFS_V2_SO_MAX_BYTES)
                return -ENOEXEC;
            payload = sh;
            got_payload = true;
        }
        if (section_name(raw, bytes, names, &sh, ".ifsmeta")) {
            /* The compiler may mark this constant identity section
             * SHF_ALLOC and SHF_GNU_RETAIN. Neither permits execution. */
            if (got_marker || sh.sh_type != SHT_PROGBITS ||
                (sh.sh_flags & SHF_EXECINSTR) || !sh.sh_size)
                return -ENOEXEC;
            marker = sh;
            got_marker = true;
        }
    }
    if (!got_payload || !got_marker ||
        !carrier_identity(raw, &marker, format))
        return -ENOEXEC;
    *inner = raw + payload.sh_offset;
    *inner_size = payload.sh_size;
    return 0;
}

static bool loaded(const struct ifs_v2_image_plan *plan, u64 position,
                   u64 bytes, u32 required, u32 forbidden)
{
    unsigned int i;
    for (i = 0; i < plan->count; ++i) {
        const struct ifs_v2_load_segment *s = &plan->loads[i];
        if (position >= s->address &&
            span(position - s->address, bytes, s->memory_bytes) &&
            (s->flags & required) == required && !(s->flags & forbidden))
            return true;
    }
    return false;
}

static int inner_plan(const u8 *raw, size_t bytes,
                      struct ifs_v2_image_plan *plan)
{
    Elf64_Ehdr elf;
    Elf64_Shdr names, symbols = {}, strings = {}, relocations = {};
    Elf64_Phdr dynamic = {}, relro = {};
    bool found_sym = false, found_str = false, found_rela = false;
    u64 dynsym_addr = 0, dynstr_addr = 0, dynstr_bytes = 0;
    u64 dynrela_addr = 0, dynrela_bytes = 0;
    u64 previous_target = 0;
    bool terminated = false;
    unsigned int i, entry_count = 0;
    int rc = -ENOEXEC;

    if (bytes > IFS_V2_SO_MAX_BYTES || !elf_header(raw, bytes, &elf))
        return -ENOEXEC;
    memset(plan, 0, sizeof(*plan));
    plan->source = raw;
    plan->source_bytes = bytes;
    for (i = 0; i < elf.e_phnum; ++i) {
        Elf64_Phdr ph;
        unsigned int j;
        program(raw, &elf, i, &ph);
        if (ph.p_type == PT_INTERP || ph.p_type == PT_TLS ||
            (ph.p_type == PT_GNU_STACK && (ph.p_flags & PF_X)))
            return rc;
        if (ph.p_type == PT_DYNAMIC) {
            if (dynamic.p_type || !ph.p_filesz ||
                ph.p_filesz % sizeof(Elf64_Dyn) ||
                ph.p_filesz > 128u * sizeof(Elf64_Dyn) ||
                !span(ph.p_offset, ph.p_filesz, bytes))
                return rc;
            dynamic = ph;
        }
        if (ph.p_type == PT_GNU_RELRO) {
            if (relro.p_type || !ph.p_memsz ||
                !span(ph.p_vaddr, ph.p_memsz,
                      IFS_V2_IMAGE_MAX_BYTES) ||
                ph.p_filesz > ph.p_memsz)
                return rc;
            relro = ph;
        }
        if (ph.p_type != PT_LOAD)
            continue;
        if (plan->count == IFS_V2_LOAD_MAX || !ph.p_memsz ||
            ph.p_filesz > ph.p_memsz ||
            !span(ph.p_offset, ph.p_filesz, bytes) ||
            !span(ph.p_vaddr, ph.p_memsz, IFS_V2_IMAGE_MAX_BYTES) ||
            !(ph.p_flags & PF_R) || (ph.p_flags & ~(PF_R | PF_W | PF_X)) ||
            ((ph.p_flags & (PF_W | PF_X)) == (PF_W | PF_X)) ||
            (ph.p_align > IFS_V2_PAGESIZE) ||
            (ph.p_align && (ph.p_align & (ph.p_align - 1))) ||
            ((ph.p_vaddr & 4095) != (ph.p_offset & 4095)))
            return rc;
        for (j = 0; j < plan->count; ++j) {
            const struct ifs_v2_load_segment *prior = &plan->loads[j];
            u64 end_a = round_up(ph.p_vaddr + ph.p_memsz,
                                 IFS_V2_PAGESIZE);
            u64 end_b = round_up(prior->address + prior->memory_bytes,
                                 IFS_V2_PAGESIZE);
            if ((ph.p_vaddr & ~4095ULL) < end_b &&
                (prior->address & ~4095ULL) < end_a)
                return rc;
        }
        plan->loads[plan->count++] = (struct ifs_v2_load_segment){
            .source = ph.p_offset,
            .address = ph.p_vaddr,
            .file_bytes = ph.p_filesz,
            .memory_bytes = ph.p_memsz,
            .flags = ph.p_flags,
        };
        if (ph.p_vaddr + ph.p_memsz > plan->memory_bytes)
            plan->memory_bytes = ph.p_vaddr + ph.p_memsz;
    }
    if (!plan->count || !dynamic.p_type ||
        !loaded(plan, 0, sizeof(Elf64_Ehdr), PF_R, PF_W | PF_X) ||
        !loaded(plan, dynamic.p_vaddr, dynamic.p_filesz, PF_R, PF_X))
        return rc;
    plan->memory_bytes = round_up(plan->memory_bytes, 4096ULL);

    /* PIE constant callback tables typically contain relocatable
     * function pointers and live in .data.rel.ro, which starts RW.
     * Admit them only if a signed PT_GNU_RELRO segment encloses them
     * and every page in that segment can be made read-only in the
     * Kernel before calling even the first module function. */
    if (relro.p_type) {
        u64 first = round_down(relro.p_vaddr, IFS_V2_PAGESIZE);
        u64 last = round_up(relro.p_vaddr + relro.p_memsz,
                            IFS_V2_PAGESIZE);
        bool page_range_owned = false;

        if (!loaded(plan, relro.p_vaddr, relro.p_memsz,
                    PF_R | PF_W, PF_X))
            return rc;
        for (i = 0; i < plan->count; ++i) {
            const struct ifs_v2_load_segment *s = &plan->loads[i];
            u64 begin = round_down(s->address, IFS_V2_PAGESIZE);
            u64 end = round_up(s->address + s->memory_bytes,
                               IFS_V2_PAGESIZE);

            if ((s->flags & (PF_R | PF_W | PF_X)) ==
                (PF_R | PF_W) && first >= begin && last <= end) {
                page_range_owned = true;
                break;
            }
        }
        if (!page_range_owned)
            return rc;
        plan->relro_start = relro.p_vaddr;
        plan->relro_bytes = relro.p_memsz;
    }
    section(raw, &elf, elf.e_shstrndx, &names);
    if (names.sh_type != SHT_STRTAB ||
        !span(names.sh_offset, names.sh_size, bytes))
        return rc;
    for (i = 1; i < elf.e_shnum; ++i) {
        Elf64_Shdr sh;
        section(raw, &elf, i, &sh);
        if (sh.sh_type != SHT_NOBITS &&
            !span(sh.sh_offset, sh.sh_size, bytes))
            return rc;
        if ((sh.sh_flags & SHF_ALLOC) && sh.sh_size &&
            !loaded(plan, sh.sh_addr, sh.sh_size, PF_R, 0))
            return rc;
        if (sh.sh_type == SHT_DYNSYM) {
            if (found_sym || sh.sh_entsize != sizeof(Elf64_Sym) ||
                !sh.sh_size || sh.sh_size % sizeof(Elf64_Sym) ||
                sh.sh_size > IFS_V2_MAX_SYMS * sizeof(Elf64_Sym) ||
                !loaded(plan, sh.sh_addr, sh.sh_size, PF_R, PF_X))
                return rc;
            symbols = sh;
            found_sym = true;
        }
        if (section_name(raw, bytes, names, &sh, ".dynstr")) {
            if (found_str || sh.sh_type != SHT_STRTAB ||
                !sh.sh_size || !loaded(plan, sh.sh_addr,
                                       sh.sh_size, PF_R, PF_X))
                return rc;
            strings = sh;
            found_str = true;
        }
        if (sh.sh_type == SHT_RELA && sh.sh_size) {
            if (found_rela || sh.sh_entsize != sizeof(Elf64_Rela) ||
                sh.sh_size % sizeof(Elf64_Rela) ||
                sh.sh_size > IFS_V2_MAX_RELOCS * sizeof(Elf64_Rela) ||
                !loaded(plan, sh.sh_addr, sh.sh_size, PF_R, PF_X))
                return rc;
            relocations = sh;
            found_rela = true;
        }
        if (sh.sh_type == SHT_REL || sh.sh_type == SHT_RELR)
            return rc;
    }
    if (!found_sym || !found_str ||
        symbols.sh_link >= elf.e_shnum ||
        symbols.sh_link == elf.e_shstrndx)
        return rc;
    {
        Elf64_Shdr linked;
        section(raw, &elf, symbols.sh_link, &linked);
        if (linked.sh_offset != strings.sh_offset ||
            linked.sh_size != strings.sh_size)
            return rc;
    }
    for (i = 0; i < dynamic.p_filesz / sizeof(Elf64_Dyn); ++i) {
        Elf64_Dyn entry;
        memcpy(&entry, raw + dynamic.p_offset + i * sizeof(entry),
               sizeof(entry));
        if (entry.d_tag == DT_NULL) {
            terminated = true;
            break;
        }
        switch (entry.d_tag) {
        case DT_NEEDED: case DT_PLTRELSZ: case DT_PLTGOT:
        case DT_INIT: case DT_FINI: case DT_SONAME: case DT_RPATH:
        case DT_REL: case DT_RELSZ: case DT_RELENT:
        case DT_BIND_NOW: case DT_INIT_ARRAY: case DT_FINI_ARRAY:
        case DT_RUNPATH: case DT_PREINIT_ARRAY: case DT_JMPREL:
            return rc;
        case DT_SYMTAB: dynsym_addr = entry.d_un.d_ptr; break;
        case DT_STRTAB: dynstr_addr = entry.d_un.d_ptr; break;
        case DT_STRSZ: dynstr_bytes = entry.d_un.d_val; break;
        case DT_RELA: dynrela_addr = entry.d_un.d_ptr; break;
        case DT_RELASZ: dynrela_bytes = entry.d_un.d_val; break;
        case DT_SYMENT:
            if (entry.d_un.d_val != sizeof(Elf64_Sym))
                return rc;
            break;
        case DT_RELAENT:
            if (entry.d_un.d_val != sizeof(Elf64_Rela))
                return rc;
            break;
        /* -Bsymbolic resolves local definitions before a shared ELF is
         * embedded. It cannot introduce external imports. The separate
         * undefined-symbol scan and RELATIVE-only relocations still apply.
         * Rejecting this flag would reject every canonical freestanding
         * EXT4 V2 provider built with the existing firmware link flags. */
        case DT_SYMBOLIC: break;
        default: break;
        }
    }
    if (!terminated || dynsym_addr != symbols.sh_addr ||
        dynstr_addr != strings.sh_addr ||
        dynstr_bytes != strings.sh_size ||
        dynrela_addr != (found_rela ? relocations.sh_addr : 0) ||
        dynrela_bytes != (found_rela ? relocations.sh_size : 0))
        return rc;
    for (i = 1; i < symbols.sh_size / sizeof(Elf64_Sym); ++i) {
        Elf64_Sym symbol;
        const char *name;
        size_t available;
        memcpy(&symbol, raw + symbols.sh_offset + i * sizeof(symbol),
               sizeof(symbol));
        if (!symbol.st_shndx || symbol.st_shndx >= elf.e_shnum ||
            symbol.st_name >= strings.sh_size ||
            !loaded(plan, symbol.st_value,
                    symbol.st_size ? symbol.st_size : 1, PF_R, 0))
            return rc;
        name = (const char *)raw + strings.sh_offset + symbol.st_name;
        available = strings.sh_size - symbol.st_name;
        if (strnlen(name, available) >= available)
            return rc;
        if (strcmp(name, IFS_V2_EXPORT))
            continue;
        if (ELF64_ST_TYPE(symbol.st_info) != STT_FUNC ||
            !symbol.st_size ||
            !loaded(plan, symbol.st_value, symbol.st_size,
                    PF_R | PF_X, PF_W))
            return rc;
        plan->entry = symbol.st_value;
        ++entry_count;
    }
    if (entry_count != 1)
        return rc;
    for (i = 0; found_rela && i < relocations.sh_size /
                                   sizeof(Elf64_Rela); ++i) {
        Elf64_Rela rela;
        memcpy(&rela, raw + relocations.sh_offset + i * sizeof(rela),
               sizeof(rela));
        if (ELF64_R_TYPE(rela.r_info) != R_X86_64_RELATIVE ||
            ELF64_R_SYM(rela.r_info) != 0 ||
            rela.r_addend < 0 || (rela.r_offset & 7) ||
            (i && rela.r_offset <= previous_target) ||
            !loaded(plan, rela.r_offset, sizeof(u64), PF_W, PF_X) ||
            !loaded(plan, rela.r_addend, 1, PF_R, 0))
            return rc;
        previous_target = rela.r_offset;
    }
    plan->rela = relocations;
    plan->relocations = found_rela ?
                        relocations.sh_size / sizeof(Elf64_Rela) : 0;
    return 0;
}

int ifs_v2_inspect_elf(const void *carrier, size_t bytes,
                       const char *format, struct ifs_v2_image_plan *plan)
{
    const u8 *source = carrier;
    size_t length = bytes;
    int ret;

    if (!carrier || !format || !*format || strlen(format) > 63 ||
        !plan || !bytes || bytes > IFS_V2_SO_MAX_BYTES)
        return -EINVAL;
    /* A directly installed, signed freestanding image is also allowed. */
    ret = inner_plan(source, length, plan);
    if (!ret)
        return 0;
    ret = extract_carrier(source, length, format, &source, &length);
    if (ret)
        return ret;
    return inner_plan(source, length, plan);
}
