#ifndef ENVSENSOR_SENSOR_H
#define ENVSENSOR_SENSOR_H

#include <stdint.h>

typedef struct {
    int16_t temperature_centi_c; /* e.g. 2153 == 21.53C */
    uint16_t humidity_permille;  /* e.g. 452 == 45.2% RH */
    uint16_t crc;                /* crc16_ccitt over the fields above */
} sensor_packet_t;

/* Deterministic pseudo-sensor: same sample_index always yields the same
 * reading. Stands in for a real ADC/I2C sensor read so the demo build is
 * reproducible without hardware. */
sensor_packet_t sensor_read(uint32_t sample_index);

int sensor_packet_is_valid(const sensor_packet_t *pkt);

#endif /* ENVSENSOR_SENSOR_H */
