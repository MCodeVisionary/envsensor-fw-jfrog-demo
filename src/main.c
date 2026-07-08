#include "board.h"
#include "interop_checksum.h"
#include "sensor.h"
#include "version.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    printf("envsensor-fw v%d.%d.%d (%s) board=%s git=%s built=%ld\n",
           FW_VERSION_MAJOR, FW_VERSION_MINOR, FW_VERSION_PATCH,
           FW_BOARD_NAME, BOARD_NAME, FW_GIT_COMMIT, (long)FW_BUILD_EPOCH);

    for (uint32_t i = 0; i < 5; i++) {
        sensor_packet_t pkt = sensor_read(i);

        uint8_t buf[4];
        memcpy(&buf[0], &pkt.temperature_centi_c, sizeof(pkt.temperature_centi_c));
        memcpy(&buf[2], &pkt.humidity_permille, sizeof(pkt.humidity_permille));

        printf("sample[%u] temp=%d.%02dC rh=%u.%u%% valid=%s interop_crc32=%08x\n",
               i,
               pkt.temperature_centi_c / 100, pkt.temperature_centi_c % 100,
               pkt.humidity_permille / 10, pkt.humidity_permille % 10,
               sensor_packet_is_valid(&pkt) ? "yes" : "no",
               interop_crc32(buf, sizeof(buf)));
    }

    return 0;
}
