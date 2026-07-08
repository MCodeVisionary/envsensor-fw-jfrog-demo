#include "interop_checksum.h"

#include "zlib.h"

uint32_t interop_crc32(const uint8_t *data, size_t len)
{
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef *)data, (uInt)len);
    return (uint32_t)crc;
}
