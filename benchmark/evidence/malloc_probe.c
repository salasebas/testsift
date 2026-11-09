#include <stddef.h>

#if defined(__APPLE__)
#include <malloc/malloc.h>

size_t evidence_malloc_bytes(void) {
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);
    return stats.size_in_use;
}
#else
#include <malloc.h>

size_t evidence_malloc_bytes(void) {
    struct mallinfo2 info = mallinfo2();
    return info.uordblks + info.hblkhd;
}
#endif
