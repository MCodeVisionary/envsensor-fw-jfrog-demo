#include "crc.h"

#include <stdio.h>
#include <string.h>

int main(void)
{
    /* Standard CRC-16/CCITT-FALSE check value for ASCII "123456789". */
    const uint8_t check[] = "123456789";
    uint16_t got = crc16_ccitt(check, strlen((const char *)check));
    if (got != 0x29B1u) {
        fprintf(stderr, "FAIL: check vector: got 0x%04X, want 0x29B1\n", got);
        return 1;
    }

    /* Empty input leaves the CRC at its initial value. */
    uint16_t empty = crc16_ccitt(NULL, 0);
    if (empty != 0xFFFFu) {
        fprintf(stderr, "FAIL: empty input: got 0x%04X, want 0xFFFF\n", empty);
        return 1;
    }

    printf("PASS: crc16_ccitt known vectors\n");
    return 0;
}
