#ifndef ENVSENSOR_CRC_H
#define ENVSENSOR_CRC_H

#include <stddef.h>
#include <stdint.h>

/* CRC-16/CCITT-FALSE, polynomial 0x1021, initial value 0xFFFF.
 * Pure integer math, no floating point, no platform intrinsics —
 * bit-identical output on any target, host or embedded. */
uint16_t crc16_ccitt(const uint8_t *data, size_t len);

#endif /* ENVSENSOR_CRC_H */
