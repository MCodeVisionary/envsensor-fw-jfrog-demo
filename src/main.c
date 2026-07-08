#include "board.h"
#include "sensor.h"
#include "version.h"

#include <stdint.h>
#include <stdio.h>

int main(void)
{
    printf("envsensor-fw v%d.%d.%d (%s) board=%s git=%s built=%ld\n",
           FW_VERSION_MAJOR, FW_VERSION_MINOR, FW_VERSION_PATCH,
           FW_BOARD_NAME, BOARD_NAME, FW_GIT_COMMIT, (long)FW_BUILD_EPOCH);

    for (uint32_t i = 0; i < 5; i++) {
        sensor_packet_t pkt = sensor_read(i);
        printf("sample[%u] temp=%d.%02dC rh=%u.%u%% valid=%s\n",
               i,
               pkt.temperature_centi_c / 100, pkt.temperature_centi_c % 100,
               pkt.humidity_permille / 10, pkt.humidity_permille % 10,
               sensor_packet_is_valid(&pkt) ? "yes" : "no");
    }

    return 0;
}
