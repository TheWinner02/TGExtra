#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <string.h>

#define TG_BIND_OPCODE_MASK                             0xF0
#define TG_BIND_IMMEDIATE_MASK                          0x0F
#define TG_BIND_OPCODE_DONE                             0x00
#define TG_BIND_OPCODE_SET_DYLIB_ORDINAL_IMM            0x10
#define TG_BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB           0x20
#define TG_BIND_OPCODE_SET_DYLIB_SPECIAL_IMM            0x30
#define TG_BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM    0x40
#define TG_BIND_OPCODE_SET_TYPE_IMM                     0x50
#define TG_BIND_OPCODE_SET_ADDEND_SLEB                  0x60
#define TG_BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB      0x70
#define TG_BIND_OPCODE_ADD_ADDR_ULEB                    0x80
#define TG_BIND_OPCODE_DO_BIND                          0x90
#define TG_BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB            0xA0
#define TG_BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED      0xB0
#define TG_BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB 0xC0

static uint64_t TGExtraReadULEB128(const uint8_t **cursor, const uint8_t *end) {
    uint64_t result = 0;
    unsigned shift = 0;
    while (*cursor < end && shift < 64) {
        uint8_t byte = *(*cursor)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static int64_t TGExtraReadSLEB128(const uint8_t **cursor, const uint8_t *end) {
    int64_t result = 0;
    unsigned shift = 0;
    uint8_t byte = 0;
    while (*cursor < end && shift < 64) {
        byte = *(*cursor)++;
        result |= ((int64_t)(byte & 0x7f)) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) break;
    }
    if (shift < 64 && (byte & 0x40)) result |= -((int64_t)1 << shift);
    return result;
}

static int TGExtraReplaceBinding(void **binding,
                                 void *replacement,
                                 void **original) {
    if (original && *original == NULL) *original = *binding;

    vm_address_t address = (vm_address_t)binding;
    vm_address_t page = address & ~((vm_address_t)vm_page_size - 1);
    kern_return_t protection = vm_protect(mach_task_self(),
                                          page,
                                          vm_page_size,
                                          false,
                                          VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (protection != KERN_SUCCESS) return 0;
    *binding = replacement;
    return 1;
}

static BOOL TGExtraSymbolMatches(const char *candidate, const char *symbolName) {
    if (!candidate) return NO;
    if (candidate[0] == '_') candidate++;
    return strcmp(candidate, symbolName) == 0;
}

static int TGExtraRebindDyldInfo(const uint8_t *stream,
                                 size_t streamSize,
                                 BOOL isLazy,
                                 intptr_t slide,
                                 const struct segment_command_64 **segments,
                                 uint32_t segmentCount,
                                 const char *symbolName,
                                 void *replacement,
                                 void **original) {
    if (!stream || streamSize == 0) return 0;

    const uint8_t *cursor = stream;
    const uint8_t *end = stream + streamSize;
    const char *currentSymbol = NULL;
    uint32_t segmentIndex = UINT32_MAX;
    uint64_t segmentOffset = 0;
    int replaced = 0;

#define TG_EXTRA_DO_BIND() do { \
    if (segmentIndex < segmentCount && currentSymbol && \
        segmentOffset + sizeof(void *) <= segments[segmentIndex]->vmsize && \
        TGExtraSymbolMatches(currentSymbol, symbolName)) { \
        void **binding = (void **)((uintptr_t)slide + \
                                   segments[segmentIndex]->vmaddr + \
                                   segmentOffset); \
        replaced += TGExtraReplaceBinding(binding, replacement, original); \
    } \
} while (0)

    while (cursor < end) {
        uint8_t byte = *cursor++;
        uint8_t opcode = byte & TG_BIND_OPCODE_MASK;
        uint8_t immediate = byte & TG_BIND_IMMEDIATE_MASK;
        switch (opcode) {
            case TG_BIND_OPCODE_DONE:
                if (!isLazy) {
                    cursor = end;
                } else {
                    currentSymbol = NULL;
                    segmentIndex = UINT32_MAX;
                    segmentOffset = 0;
                }
                break;
            case TG_BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
            case TG_BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            case TG_BIND_OPCODE_SET_TYPE_IMM:
                break;
            case TG_BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
                (void)TGExtraReadULEB128(&cursor, end);
                break;
            case TG_BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
                currentSymbol = (const char *)cursor;
                const void *terminator = memchr(cursor, '\0', (size_t)(end - cursor));
                if (!terminator) {
                    cursor = end;
                } else {
                    cursor = (const uint8_t *)terminator + 1;
                }
                break;
            }
            case TG_BIND_OPCODE_SET_ADDEND_SLEB:
                (void)TGExtraReadSLEB128(&cursor, end);
                break;
            case TG_BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                segmentIndex = immediate;
                segmentOffset = TGExtraReadULEB128(&cursor, end);
                break;
            case TG_BIND_OPCODE_ADD_ADDR_ULEB:
                segmentOffset += TGExtraReadULEB128(&cursor, end);
                break;
            case TG_BIND_OPCODE_DO_BIND:
                TG_EXTRA_DO_BIND();
                segmentOffset += sizeof(void *);
                break;
            case TG_BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
                TG_EXTRA_DO_BIND();
                segmentOffset += sizeof(void *) + TGExtraReadULEB128(&cursor, end);
                break;
            case TG_BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
                TG_EXTRA_DO_BIND();
                segmentOffset += sizeof(void *) + immediate * sizeof(void *);
                break;
            case TG_BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
                uint64_t count = TGExtraReadULEB128(&cursor, end);
                uint64_t skip = TGExtraReadULEB128(&cursor, end);
                for (uint64_t index = 0; index < count; index++) {
                    TG_EXTRA_DO_BIND();
                    segmentOffset += sizeof(void *) + skip;
                }
                break;
            }
            default:
                cursor = end;
                break;
        }
    }

#undef TG_EXTRA_DO_BIND
    return replaced;
}

static int TGExtraRebindSection(const struct section_64 *section,
                                intptr_t slide,
                                struct nlist_64 *symbolTable,
                                char *stringTable,
                                uint32_t *indirectSymbolTable,
                                const char *symbolName,
                                void *replacement,
                                void **original) {
    uint32_t sectionType = section->flags & SECTION_TYPE;
    if (sectionType != S_LAZY_SYMBOL_POINTERS &&
        sectionType != S_NON_LAZY_SYMBOL_POINTERS) {
        return 0;
    }

    void **bindings = (void **)(slide + section->addr);
    uint32_t count = (uint32_t)(section->size / sizeof(void *));
    int replaced = 0;
    for (uint32_t index = 0; index < count; index++) {
        uint32_t symbolIndex = indirectSymbolTable[section->reserved1 + index];
        if (symbolIndex == INDIRECT_SYMBOL_ABS ||
            symbolIndex == INDIRECT_SYMBOL_LOCAL ||
            symbolIndex == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }

        uint32_t stringOffset = symbolTable[symbolIndex].n_un.n_strx;
        if (stringOffset == 0) continue;
        const char *candidate = stringTable + stringOffset;
        if (candidate[0] == '_') candidate++;
        if (strcmp(candidate, symbolName) != 0) continue;

        if (original && *original == NULL) {
            *original = bindings[index];
        }

        replaced += TGExtraReplaceBinding(&bindings[index], replacement, original);
    }
    return replaced;
}

int TGExtraRebindSymbol(const char *symbolName, void *replacement, void **original) {
    if (!symbolName || !replacement) return 0;
    int replaced = 0;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const struct mach_header_64 *header =
            (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
        if (!header || header->magic != MH_MAGIC_64) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
        const struct segment_command_64 *linkedit = NULL;
        const struct symtab_command *symtab = NULL;
        const struct dysymtab_command *dysymtab = NULL;
        const struct dyld_info_command *dyldInfo = NULL;
        const struct segment_command_64 *segments[64] = { 0 };
        uint32_t segmentCount = 0;

        uintptr_t cursor = (uintptr_t)header + sizeof(struct mach_header_64);
        for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment =
                    (const struct segment_command_64 *)command;
                if (segmentCount < 64) segments[segmentCount++] = segment;
                if (strcmp(segment->segname, SEG_LINKEDIT) == 0) linkedit = segment;
            } else if (command->cmd == LC_SYMTAB) {
                symtab = (const struct symtab_command *)command;
            } else if (command->cmd == LC_DYSYMTAB) {
                dysymtab = (const struct dysymtab_command *)command;
            } else if (command->cmd == LC_DYLD_INFO ||
                       command->cmd == LC_DYLD_INFO_ONLY) {
                dyldInfo = (const struct dyld_info_command *)command;
            }
            cursor += command->cmdsize;
        }

        if (!linkedit) continue;
        uintptr_t linkeditBase = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;

        if (dyldInfo) {
            replaced += TGExtraRebindDyldInfo(
                (const uint8_t *)(linkeditBase + dyldInfo->bind_off),
                dyldInfo->bind_size,
                NO,
                slide,
                segments,
                segmentCount,
                symbolName,
                replacement,
                original);
            replaced += TGExtraRebindDyldInfo(
                (const uint8_t *)(linkeditBase + dyldInfo->weak_bind_off),
                dyldInfo->weak_bind_size,
                NO,
                slide,
                segments,
                segmentCount,
                symbolName,
                replacement,
                original);
            replaced += TGExtraRebindDyldInfo(
                (const uint8_t *)(linkeditBase + dyldInfo->lazy_bind_off),
                dyldInfo->lazy_bind_size,
                YES,
                slide,
                segments,
                segmentCount,
                symbolName,
                replacement,
                original);
        }

        if (!symtab || !dysymtab) continue;
        struct nlist_64 *symbolTable =
            (struct nlist_64 *)(linkeditBase + symtab->symoff);
        char *stringTable = (char *)(linkeditBase + symtab->stroff);
        uint32_t *indirectSymbolTable =
            (uint32_t *)(linkeditBase + dysymtab->indirectsymoff);

        cursor = (uintptr_t)header + sizeof(struct mach_header_64);
        for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment =
                    (const struct segment_command_64 *)command;
                const struct section_64 *sections =
                    (const struct section_64 *)(segment + 1);
                for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                    replaced += TGExtraRebindSection(&sections[sectionIndex],
                                                     slide,
                                                     symbolTable,
                                                     stringTable,
                                                     indirectSymbolTable,
                                                     symbolName,
                                                     replacement,
                                                     original);
                }
            }
            cursor += command->cmdsize;
        }
    }
    return replaced;
}

struct TGExtraDyldInterposeTuple {
    const void *replacement;
    const void *replacee;
};

typedef void (*TGExtraDyldDynamicInterposeFunction)(
    const struct mach_header *header,
    const struct TGExtraDyldInterposeTuple tuples[],
    size_t count
);

int TGExtraDynamicInterpose(void *replacee, void *replacement) {
    if (!replacee || !replacement) return 0;

    TGExtraDyldDynamicInterposeFunction dynamicInterpose =
        (TGExtraDyldDynamicInterposeFunction)dlsym(RTLD_DEFAULT,
                                                   "dyld_dynamic_interpose");
    if (!dynamicInterpose) {
        dynamicInterpose =
            (TGExtraDyldDynamicInterposeFunction)dlsym(RTLD_DEFAULT,
                                                       "_dyld_dynamic_interpose");
    }
    if (!dynamicInterpose) return 0;

    const struct TGExtraDyldInterposeTuple tuple = {
        .replacement = replacement,
        .replacee = replacee
    };
    int interposedImages = 0;
    const uint32_t imageCount = _dyld_image_count();
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const struct mach_header *header = _dyld_get_image_header(imageIndex);
        if (!header) continue;
        dynamicInterpose(header, &tuple, 1);
        interposedImages += 1;
    }
    return interposedImages;
}

extern void TGExtraInstallNativeScheduleHook(void);

__attribute__((constructor))
static void TGExtraNativeScheduleBootstrap(void) {
    TGExtraInstallNativeScheduleHook();
}
