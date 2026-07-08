#ifndef ENVSENSOR_INTEROP_CHECKSUM_H
#define ENVSENSOR_INTEROP_CHECKSUM_H

#include <stddef.h>
#include <stdint.h>

/*
 * CRC-32 checksum kept alongside the native CRC-16 packet framing (see
 * crc.h) purely for interop with an external desktop tool that expects
 * zlib-style CRC-32 over the same sensor payload bytes. Backed by a vendored
 * copy of zlib 1.2.11's crc32() (see third_party/zlib-1.2.11/) rather than a
 * package-manager dependency, since this project has no package manager —
 * see third_party/README.md for why that's worth flagging, not copying
 * blindly.
 */
uint32_t interop_crc32(const uint8_t *data, size_t len);

#endif /* ENVSENSOR_INTEROP_CHECKSUM_H */
