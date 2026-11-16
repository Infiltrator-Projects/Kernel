// SPDX-License-Identifier: GPL-2.0-only
/*
 * InfiltratorOS format-neutral Common V2, read-only Linux VFS adapter.
 * All on-disk interpretation is performed by a verified independent SO.
 * No per-format Linux driver, FUSE, format detector or fallback is used.
 *
 * This component is not a module loader. Its verified-provider acquire
 * interface fails closed until the privileged ELF admission/executor has
 * been implemented and qualified. Registering a VFS type is NOT evidence
 * that an SO can be mounted or used as a system root.
 */
#include <linux/blkdev.h>
#include <linux/err.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/fs_context.h>
#include <linux/fs_parser.h>
#include <linux/highmem.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mount.h>
#include <linux/mutex.h>
#include <linux/pagemap.h>
#include <linux/slab.h>
#include <linux/statfs.h>
#include <linux/string.h>
#include <linux/uio.h>
#include <linux/user_namespace.h>
#include <linux/vmalloc.h>
#include <linux/infiltratr_fs_v2_adapter.h>

#define IFS_V2_MAGIC 0x49534632U

/* The mount format names the *independent* provider under
 * /System/Filesystems. No format-specific code belongs in the adapter.
 * A future qualified auto-discovery path may select this automatically. */
struct ifs_v2_mount_options {
    char format[64];
};
enum { Opt_format };
static const struct fs_parameter_spec ifs_v2_params[] = {
    fsparam_string("format", Opt_format),
    {}
};
static bool ifs_v2_valid_format(const char *name)
{
    size_t n;
    if (!name || !*name)
        return false;
    for (n = 0; n < 63 && name[n]; ++n)
        if (!(name[n] >= 'a' && name[n] <= 'z') &&
            !(name[n] >= '0' && name[n] <= '9') &&
            name[n] != '_' && name[n] != '-')
            return false;
    return n && n < 64 && !name[n];
}


struct ifs_v2_mount {
    struct mutex io_lock;
    struct file *source;
    struct ifs_v2_host host;
    struct ifs_v2_verified provider;
    struct ifs_v2_volume_info info;
    void *volume;
};

static int ifs_v2_error(int code)
{
    switch (code) {
    case 0: return 0;
    case IFS_V2_NOT_FOUND: return -ENOENT;
    case IFS_V2_CORRUPT: return -EUCLEAN;
    case IFS_V2_IO_ERROR: return -EIO;
    case IFS_V2_UNSUPPORTED: return -EOPNOTSUPP;
    default: return -EINVAL;
    }
}

static void *ifs_v2_alloc(void *unused, size_t bytes)
{
    return kmalloc(bytes, GFP_KERNEL);
}

static void ifs_v2_free(void *unused, void *ptr)
{
    kfree(ptr);
}

/* File-backed block I/O can operate on the real block device or a loop
 * test-image, always through the same verified host callback. */
static int ifs_v2_read_at(void *cookie, u64 offset, void *buffer, u32 bytes)
{
    struct ifs_v2_mount *m = cookie;
    loff_t pos;
    ssize_t read;

    if (!buffer || !bytes || offset > m->host.volume_bytes ||
        bytes > m->host.volume_bytes - offset ||
        bytes > m->host.maximum_transfer_bytes ||
        offset % m->host.logical_sector_bytes ||
        bytes % m->host.logical_sector_bytes ||
        offset > LLONG_MAX)
        return -EINVAL;
    pos = (loff_t)offset;
    read = kernel_read(m->source, buffer, bytes, &pos);
    return read == bytes ? 0 : -EIO;
}

static int ifs_v2_stat(struct ifs_v2_mount *m, const char *path,
                       struct ifs_v2_entry *entry)
{
    int ret;

    mutex_lock(&m->io_lock);
    ret = m->provider.core->stat(m->volume, path, entry);
    mutex_unlock(&m->io_lock);
    return ifs_v2_error(ret);
}

static struct inode *ifs_v2_make_inode(struct super_block *sb,
                                      const char *path,
                                      const struct ifs_v2_entry *entry);

static struct dentry *ifs_v2_lookup(struct inode *parent,
                                   struct dentry *dentry, unsigned int flags)
{
    struct ifs_v2_mount *m = parent->i_sb->s_fs_info;
    const char *base = parent->i_private;
    struct ifs_v2_entry entry = {};
    struct inode *inode;
    char *path;
    char name[IFS_V2_MAX_NAME + 1] = {};
    int ret;

    if (!base || !dentry->d_name.len ||
        dentry->d_name.len > IFS_V2_MAX_NAME)
        return ERR_PTR(-ENAMETOOLONG);
    path = kasprintf(GFP_KERNEL, "%s%s%.*s", base,
                     !strcmp(base, "/") ? "" : "/",
                     (int)dentry->d_name.len, dentry->d_name.name);
    if (!path)
        return ERR_PTR(-ENOMEM);
    if (strlen(path) >= IFS_V2_PATH_MAX) {
        kfree(path);
        return ERR_PTR(-ENAMETOOLONG);
    }

    entry.structure_bytes = sizeof(entry);
    entry.name = name;
    entry.name_capacity = sizeof(name);
    ret = ifs_v2_stat(m, path, &entry);
    if (ret == -ENOENT) {
        d_add(dentry, NULL);
        kfree(path);
        return NULL;
    }
    if (ret) {
        kfree(path);
        return ERR_PTR(ret);
    }
    inode = ifs_v2_make_inode(parent->i_sb, path, &entry);
    kfree(path);
    if (IS_ERR(inode))
        return ERR_CAST(inode);
    d_add(dentry, inode);
    return NULL;
}

/* Read from the provider into the kernel page cache so that ordinary
 * file reads, executable mappings and demand-paged binaries all use the
 * same Common V2 provider. Never switch to a format-specific native reader. */
static int ifs_v2_read_folio(struct file *file, struct folio *folio)
{
    struct inode *inode = folio->mapping->host;
    struct ifs_v2_mount *m = inode->i_sb->s_fs_info;
    const char *path = inode->i_private;
    u64 start = folio_pos(folio);
    loff_t size = i_size_read(inode);
    size_t folio_bytes = folio_size(folio);
    size_t wanted = 0, done = 0;
    int ret = 0;

    if (!path) {
        folio_end_read(folio, false);
        return -EINVAL;
    }
    if (start < size)
        wanted = min_t(u64, folio_bytes, (u64)size - start);

    /* A Common V2 read is strictly capped to the provider host transfer
     * bound. Iterate high-order folios one mapped page at a time. */
    while (done < folio_bytes) {
        size_t chunk = min_t(size_t, PAGE_SIZE, folio_bytes - done);
        size_t requested = done < wanted ?
                           min_t(size_t, chunk, wanted - done) : 0;
        void *mapping = kmap_local_folio(folio, done);

        if (requested && !ret) {
            mutex_lock(&m->io_lock);
            ret = ifs_v2_error(m->provider.core->read(
                    m->volume, path, start + done, mapping, requested));
            mutex_unlock(&m->io_lock);
        }
        if (ret || requested < chunk)
            memset((u8 *)mapping + (ret ? 0 : requested), 0,
                   chunk - (ret ? 0 : requested));
        kunmap_local(mapping);
        done += chunk;
    }
    folio_end_read(folio, !ret);
    return ret;
}

static const struct address_space_operations ifs_v2_aops = {
    .read_folio = ifs_v2_read_folio,
};

static int ifs_v2_iterate(struct file *file, struct dir_context *ctx)
{
    struct inode *inode = file_inode(file);
    struct ifs_v2_mount *m = inode->i_sb->s_fs_info;
    char *path = inode->i_private;
    char name[IFS_V2_MAX_NAME + 1];
    struct ifs_v2_entry entry = {};
    int ret;

    if (!dir_emit_dots(file, ctx))
        return 0;
    entry.structure_bytes = sizeof(entry);
    entry.name = name;
    entry.name_capacity = sizeof(name);
    while (ctx->pos >= 2 && ctx->pos - 2 <= U32_MAX) {
        unsigned int type;
        mutex_lock(&m->io_lock);
        ret = m->provider.core->directory_entry(
            m->volume, path, ctx->pos - 2, &entry);
        mutex_unlock(&m->io_lock);
        if (ret == IFS_V2_END)
            return 0;
        if (ret)
            return ifs_v2_error(ret);
        if (!entry.name_bytes || entry.name_bytes > IFS_V2_MAX_NAME ||
            name[entry.name_bytes] != '\0' ||
            strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, ".."))
            return -EUCLEAN;
        switch (entry.type) {
        case IFS_V2_ENTRY_DIR: type = DT_DIR; break;
        case IFS_V2_ENTRY_FILE: type = DT_REG; break;
        default: type = DT_UNKNOWN; break;
        }
        if (!dir_emit(ctx, name, entry.name_bytes,
                      ctx->pos + 1, type))
            return 0;
        ++ctx->pos;
        entry.structure_bytes = sizeof(entry);
    }
    return -EOVERFLOW;
}

static const struct file_operations ifs_v2_files = {
    .read_iter = generic_file_read_iter,
    .mmap = generic_file_mmap,
    .llseek = generic_file_llseek,
};

static const struct file_operations ifs_v2_directories = {
    .iterate_shared = ifs_v2_iterate,
    .llseek = generic_file_llseek,
};

static const struct inode_operations ifs_v2_dir_inode_ops = {
    .lookup = ifs_v2_lookup,
};

static struct inode *ifs_v2_make_inode(struct super_block *sb,
                                      const char *path,
                                      const struct ifs_v2_entry *entry)
{
    struct inode *inode;
    struct ifs_v2_mount *m = sb->s_fs_info;
    struct ifs_v2_metadata_info metadata = {
        .structure_bytes = sizeof(metadata),
    };
    kuid_t owner = GLOBAL_ROOT_UID;
    kgid_t group = GLOBAL_ROOT_GID;
    umode_t mode;
    int ret;

    if (entry->type == IFS_V2_ENTRY_DIR)
        mode = S_IFDIR | 0555;
    else if (entry->type == IFS_V2_ENTRY_FILE)
        mode = S_IFREG | 0444;
    else
        /* A symlink without a qualified READLINK method is not a file. */
        return ERR_PTR(-EOPNOTSUPP);

    /* Never guess execution bits from the filename or an EXT4-specific
     * on-disk field. The independently verified provider owns metadata. */
    if (m->provider.metadata) {
        mutex_lock(&m->io_lock);
        ret = m->provider.metadata->get(m->volume, path, &metadata);
        mutex_unlock(&m->io_lock);
        if (ret)
            return ERR_PTR(ifs_v2_error(ret));
        if (!(metadata.mask & IFS_V2_META_GET_MODE) ||
            (metadata.mode & S_IFMT) != (mode & S_IFMT))
            return ERR_PTR(-EUCLEAN);
        owner = make_kuid(&init_user_ns, metadata.owner);
        group = make_kgid(&init_user_ns, metadata.group);
        if (!uid_valid(owner) || !gid_valid(group))
            return ERR_PTR(-EUCLEAN);
        mode = (mode & S_IFMT) | (metadata.mode & 07777);
    }
    inode = new_inode(sb);
    if (!inode)
        return ERR_PTR(-ENOMEM);
    inode->i_private = kstrdup(path, GFP_KERNEL);
    if (!inode->i_private) {
        iput(inode);
        return ERR_PTR(-ENOMEM);
    }
    inode->i_ino = get_next_ino();
    inode->i_mode = mode;
    inode->i_uid = owner;
    inode->i_gid = group;
    simple_inode_init_ts(inode);
    if (S_ISDIR(mode)) {
        set_nlink(inode, 2);
        inode->i_op = &ifs_v2_dir_inode_ops;
        inode->i_fop = &ifs_v2_directories;
    } else {
        set_nlink(inode, 1);
        i_size_write(inode, entry->size_bytes);
        inode->i_mapping->a_ops = &ifs_v2_aops;
        inode->i_fop = &ifs_v2_files;
    }
    return inode;
}

static void ifs_v2_evict_inode(struct inode *inode)
{
    truncate_inode_pages_final(&inode->i_data);
    clear_inode(inode);
    kfree(inode->i_private);
}

static const struct super_operations ifs_v2_super_ops = {
    .evict_inode = ifs_v2_evict_inode,
    .statfs = simple_statfs,
};

static void ifs_v2_drop_mount(struct ifs_v2_mount *m)
{
    if (!m)
        return;
    if (m->volume)
        m->provider.core->unmount(m->volume);
    if (m->provider.release_image)
        m->provider.release_image(m->provider.image_lease);
    if (m->source)
        fput(m->source);
    kfree(m);
}

static void ifs_v2_kill_sb(struct super_block *sb)
{
    struct ifs_v2_mount *m = sb->s_fs_info;
    kill_anon_super(sb);
    ifs_v2_drop_mount(m);
}

static int ifs_v2_fill_super(struct super_block *sb, struct fs_context *fc)
{
    struct ifs_v2_mount *m;
    struct ifs_v2_entry entry = {};
    char root_name[2] = {};
    struct inode *root;
    struct file *file;
    u32 sector = 512, variant = 0;
    int ret;

    if (!fc->source || !(fc->sb_flags & SB_RDONLY))
        return -EROFS;
    if (!fc->fs_private ||
        !ifs_v2_valid_format(
            ((struct ifs_v2_mount_options *)fc->fs_private)->format))
        return -EINVAL;
    m = kzalloc(sizeof(*m), GFP_KERNEL);
    if (!m)
        return -ENOMEM;
    mutex_init(&m->io_lock);
    sb->s_fs_info = m;
    file = filp_open(fc->source, O_RDONLY | O_LARGEFILE, 0);
    if (IS_ERR(file))
        return PTR_ERR(file);
    m->source = file;
    if (!S_ISBLK(file_inode(file)->i_mode) &&
        !S_ISREG(file_inode(file)->i_mode))
        return -ENOTBLK;
    if (file_inode(file)->i_sb->s_type == sb->s_type)
        return -ELOOP;
    if (i_size_read(file_inode(file)) <= 0)
        return -ENODEV;
    if (S_ISBLK(file_inode(file)->i_mode))
        sector = bdev_logical_block_size(file_bdev(file));
    if (sector < 512 || sector > 65536 || !is_power_of_2(sector))
        return -EINVAL;

    m->host.abi_version = IFS_V2_ABI;
    m->host.structure_bytes = sizeof(m->host);
    m->host.capabilities = IFS_V2_READ_ONLY;
    m->host.volume_bytes = i_size_read(file_inode(file));
    m->host.logical_sector_bytes = sector;
    m->host.physical_sector_bytes = sector;
    m->host.maximum_transfer_bytes = round_up(IFS_V2_MAX_READ, sector);
    m->host.context = m;
    m->host.read_at = ifs_v2_read_at;
    m->host.allocate = ifs_v2_alloc;
    m->host.release = ifs_v2_free;

    /* A loader returns an already VERIFIED, executable Common V2 module.
     * An absent/untrusted module is a hard failure, never a native mount. */
    ret = ifs_v2_elf_acquire(
        ((struct ifs_v2_mount_options *)fc->fs_private)->format,
        &m->provider);
    if (ret)
        return ret;
    if (!m->provider.core ||
        (m->provider.core->header.capabilities & IFS_V2_CORE_REQUIRED)
            != IFS_V2_CORE_REQUIRED ||
        !m->provider.core->probe || !m->provider.core->mount ||
        !m->provider.core->unmount || !m->provider.core->stat ||
        !m->provider.core->directory_entry || !m->provider.core->read)
        return -ENOEXEC;
    ret = ifs_v2_error(m->provider.core->probe(&m->host, &variant));
    if (ret)
        return ret;
    m->info.structure_bytes = sizeof(m->info);
    ret = ifs_v2_error(m->provider.core->mount(
        &m->host, &m->volume, &m->info));
    if (ret)
        return ret;
    entry.structure_bytes = sizeof(entry);
    entry.name = root_name;
    entry.name_capacity = sizeof(root_name);
    ret = ifs_v2_stat(m, "/", &entry);
    if (ret || entry.type != IFS_V2_ENTRY_DIR)
        return ret ? ret : -EUCLEAN;

    sb->s_maxbytes = MAX_LFS_FILESIZE;
    sb->s_magic = IFS_V2_MAGIC;
    sb->s_flags |= SB_RDONLY | SB_NOATIME;
    sb->s_blocksize = PAGE_SIZE;
    sb->s_blocksize_bits = PAGE_SHIFT;
    sb->s_op = &ifs_v2_super_ops;
    sb->s_d_flags |= DCACHE_DONTCACHE;
    root = ifs_v2_make_inode(sb, "/", &entry);
    if (IS_ERR(root))
        return PTR_ERR(root);
    sb->s_root = d_make_root(root);
    return sb->s_root ? 0 : -ENOMEM;
}

static int ifs_v2_get_tree(struct fs_context *fc)
{
    return get_tree_nodev(fc, ifs_v2_fill_super);
}

static int ifs_v2_parse_param(struct fs_context *fc,
                              struct fs_parameter *param)
{
    struct ifs_v2_mount_options *options = fc->fs_private;
    struct fs_parse_result parsed;
    int token = fs_parse(fc, ifs_v2_params, param, &parsed);

    if (token < 0)
        return token;
    if (token != Opt_format || !param->string ||
        !ifs_v2_valid_format(param->string))
        return -EINVAL;
    strscpy(options->format, param->string, sizeof(options->format));
    return 0;
}

static void ifs_v2_free_context(struct fs_context *fc)
{
    kfree(fc->fs_private);
    fc->fs_private = NULL;
}

static const struct fs_context_operations ifs_v2_context_ops = {
    .parse_param = ifs_v2_parse_param,
    .get_tree = ifs_v2_get_tree,
    .free = ifs_v2_free_context,
};

static int ifs_v2_init_fs_context(struct fs_context *fc)
{
    struct ifs_v2_mount_options *options = kzalloc(sizeof(*options), GFP_KERNEL);

    if (!options)
        return -ENOMEM;
    fc->fs_private = options;
    fc->ops = &ifs_v2_context_ops;
    fc->sb_flags |= SB_RDONLY;
    return 0;
}

static struct file_system_type ifs_v2_type = {
    .name = "infiltratr-v2",
    .init_fs_context = ifs_v2_init_fs_context,
    .kill_sb = ifs_v2_kill_sb,
    .parameters = ifs_v2_params,
};

static int __init ifs_v2_init(void)
{
    return register_filesystem(&ifs_v2_type);
}

static void __exit ifs_v2_exit(void)
{
    unregister_filesystem(&ifs_v2_type);
}

module_init(ifs_v2_init);
module_exit(ifs_v2_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Generic read-only Common V2 filesystem VFS adapter");
