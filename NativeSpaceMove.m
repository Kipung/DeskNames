// Adapted from ferry and yabai. See THIRD_PARTY_NOTICES.txt for the MIT license.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <string.h>

typedef int64_t (*DNBridgedOperation)(void *operation);

static const char *const DNOperationSymbol = "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation";
static DNBridgedOperation DNPerform;
static Class DNMoveClass;
static SEL DNInitSelector;
static void *DNSkyLight;

static void *DNFindLocalSymbol(const char *symbolName)
{
    for (uint32_t image = 0; image < _dyld_image_count(); ++image) {
        const char *path = _dyld_get_image_name(image);
        if (!path || !strstr(path, "/SkyLight.framework/") || strcmp(strrchr(path, '/') + 1, "SkyLight") != 0) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(image);
        if (!header || header->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(image);
        const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
        const uint8_t *end = cursor + header->sizeofcmds;
        const struct segment_command_64 *linkedit = NULL;
        const struct symtab_command *symtab = NULL;
        for (uint32_t command = 0; command < header->ncmds; ++command) {
            if ((size_t)(end - cursor) < sizeof(struct load_command)) return NULL;
            const struct load_command *load = (const struct load_command *)cursor;
            if (load->cmdsize < sizeof(*load) || load->cmdsize > (size_t)(end - cursor)) return NULL;
            if (load->cmd == LC_SEGMENT_64 && load->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)load;
                if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) linkedit = segment;
            } else if (load->cmd == LC_SYMTAB && load->cmdsize >= sizeof(struct symtab_command)) {
                symtab = (const struct symtab_command *)load;
            }
            cursor += load->cmdsize;
        }
        if (!linkedit || !symtab || !symtab->strsize) return NULL;
        const uint8_t *base = (const uint8_t *)(linkedit->vmaddr - linkedit->fileoff + slide);
        const char *strings = (const char *)(base + symtab->stroff);
        const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
        for (uint32_t index = 0; index < symtab->nsyms; ++index) {
            const struct nlist_64 entry = symbols[index];
            if ((entry.n_type & N_STAB) || (entry.n_type & N_TYPE) != N_SECT || !entry.n_value || entry.n_un.n_strx >= symtab->strsize) continue;
            const char *name = strings + entry.n_un.n_strx;
            if (!memchr(name, '\0', symtab->strsize - entry.n_un.n_strx)) continue;
            if (strcmp(name, symbolName) == 0) return (void *)(entry.n_value + slide);
        }
    }
    return NULL;
}

static void DNResolve(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @autoreleasepool {
            if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 26) return;
            DNSkyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL);
            if (!DNSkyLight) return;
            Class cls = objc_getClass("SLSBridgedMoveWindowsToManagedSpaceOperation");
            SEL selector = sel_registerName("initWithWindows:spaceID:");
            Method initializer = cls ? class_getInstanceMethod(cls, selector) : NULL;
            if (!initializer || method_getNumberOfArguments(initializer) != 4) return;
            void *function = DNFindLocalSymbol(DNOperationSymbol);
            if (!function) return;
            DNMoveClass = cls;
            DNInitSelector = selector;
            DNPerform = (DNBridgedOperation)function;
        }
    });
}

int dn_can_move_window_to_space(void)
{
    DNResolve();
    return DNPerform && DNMoveClass && DNInitSelector ? 1 : 0;
}

int dn_move_window_to_space(uint32_t windowID, uint64_t spaceID)
{
    if (!windowID || !spaceID) return -1;
    if (!dn_can_move_window_to_space()) return 0;
    if (![NSThread isMainThread] || !AXIsProcessTrusted()) return -1;
    @autoreleasepool {
        id operation = nil;
        @try {
            NSArray *windows = @[@(windowID)];
            operation = [DNMoveClass alloc];
            operation = ((id (*)(id, SEL, id, uint64_t))objc_msgSend)(operation, DNInitSelector, windows, spaceID);
            if (!operation) return -1;
            // The result is not a completion status. The Swift caller must verify Space membership.
            (void)DNPerform((void *)operation);
            return 1;
        } @catch (NSException *exception) {
            (void)exception;
            return -1;
        } @finally {
            [operation release];
        }
    }
}
