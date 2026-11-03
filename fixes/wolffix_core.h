/* Shader patching for the Wolf Among Us trail fix. Plain C, so it builds and is tested on macOS too. */
#ifndef WOLFFIX_CORE_H
#define WOLFFIX_CORE_H

#include <stddef.h>

/* For a DXBC shader that reads MSAA samples 4..7 with constant sample indices, returns a
 * copy (free() it) that reads samples 0..3 instead, with its checksum updated; *count is
 * the number of reads changed. Returns NULL, with *count 0, when there is nothing to change. */
void *wolffix_remap_samples(const void *dxbc, size_t size, int *count);

/* Writes the DXBC container checksum (bytes 4..19) for the rest of the container. */
void wolffix_dxbc_checksum(unsigned char *dxbc, size_t size);

#endif
