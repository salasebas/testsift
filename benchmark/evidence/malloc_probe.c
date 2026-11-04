#include <malloc.h>
#include <stddef.h>

size_t evidence_malloc_bytes(void) {
    struct mallinfo2 info = mallinfo2();
    return info.uordblks + info.hblkhd;
}
