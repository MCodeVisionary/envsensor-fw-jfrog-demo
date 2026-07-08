#include "sensor.h"
#include "board.h"
#include "crc.h"

#include <string.h>

sensor_packet_t sensor_read(uint32_t sample_index)
{
    sensor_packet_t pkt;

    /* Deterministic synthetic waveform, offset per-board by CALIBRATION_OFFSET
     * so BOARD_A and BOARD_B produce different but reproducible readings. */
    pkt.temperature_centi_c = (int16_t)(2100 + (int)(sample_index % 50) + CALIBRATION_OFFSET);
    pkt.humidity_permille = (uint16_t)(400 + (sample_index * 7) % 200);

    uint8_t buf[4];
    memcpy(&buf[0], &pkt.temperature_centi_c, sizeof(pkt.temperature_centi_c));
    memcpy(&buf[2], &pkt.humidity_permille, sizeof(pkt.humidity_permille));
    pkt.crc = crc16_ccitt(buf, sizeof(buf));

    return pkt;
}

int sensor_packet_is_valid(const sensor_packet_t *pkt)
{
    uint8_t buf[4];
    memcpy(&buf[0], &pkt->temperature_centi_c, sizeof(pkt->temperature_centi_c));
    memcpy(&buf[2], &pkt->humidity_permille, sizeof(pkt->humidity_permille));
    return crc16_ccitt(buf, sizeof(buf)) == pkt->crc;
}
