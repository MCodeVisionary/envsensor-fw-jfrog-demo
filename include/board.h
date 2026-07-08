#ifndef ENVSENSOR_BOARD_H
#define ENVSENSOR_BOARD_H

/*
 * Board configuration is selected at CMake configure time (-DBOARD=BOARD_A|BOARD_B)
 * and baked into the binary. Each board pins its own sampling cadence and
 * calibration offset, mirroring how a real product line shares one firmware
 * codebase across hardware revisions with a 10-40 year support tail.
 */

#if defined(BOARD_A)
#define BOARD_NAME            "BOARD_A"
#define SAMPLE_INTERVAL_MS    1000
#define CALIBRATION_OFFSET    (-2)
#elif defined(BOARD_B)
#define BOARD_NAME            "BOARD_B"
#define SAMPLE_INTERVAL_MS    500
#define CALIBRATION_OFFSET    (3)
#else
#error "No BOARD defined. Configure with -DBOARD=BOARD_A or -DBOARD=BOARD_B"
#endif

#endif /* ENVSENSOR_BOARD_H */
