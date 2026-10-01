#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <string.h>

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

        vm_address_t address = (vm_address_t)&bindings[index];
        vm_address_t page = address & ~((vm_address_t)vm_page_size - 1);
        kern_return_t protection = vm_protect(mach_task_self(),
                                              page,
                                              vm_page_size,
                                              false,
                                              VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (protection != KERN_SUCCESS) continue;
        bindings[index] = replacement;
        replaced++;
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

        uintptr_t cursor = (uintptr_t)header + sizeof(struct mach_header_64);
        for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment =
                    (const struct segment_command_64 *)command;
                if (strcmp(segment->segname, SEG_LINKEDIT) == 0) linkedit = segment;
            } else if (command->cmd == LC_SYMTAB) {
                symtab = (const struct symtab_command *)command;
            } else if (command->cmd == LC_DYSYMTAB) {
                dysymtab = (const struct dysymtab_command *)command;
            }
            cursor += command->cmdsize;
        }

        if (!linkedit || !symtab || !dysymtab) continue;
        uintptr_t linkeditBase = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
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

extern void TGExtraInstallNativeScheduleHook(void);

__attribute__((constructor))
static void TGExtraNativeScheduleBootstrap(void) {
    TGExtraInstallNativeScheduleHook();
}
