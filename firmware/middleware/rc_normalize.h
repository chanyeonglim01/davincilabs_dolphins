/**
 * @file rc_normalize.h
 * @brief SBUS to normalized RC command conversion
 *
 * Converts raw SBUS channels to [-1.0, +1.0] with deadband and trim.
 */
#ifndef RC_NORMALIZE_H
#define RC_NORMALIZE_H

#include <stdint.h>
#include <stdbool.h>

/* RC channel assignments (FrSky/OpenTX convention) */
#define RC_CH_ROLL      0   /* Aileron   (A) */
#define RC_CH_PITCH     1   /* Elevator  (E) */
#define RC_CH_THROTTLE  2   /* Throttle  (T) - tail freq */
#define RC_CH_YAW       3   /* Rudder    (R) */
#define RC_CH_MODE      4   /* CH5: mode switch */
#define RC_NUM_CMD       5

/* Deadband threshold */
#define RC_DEADBAND     0.05f

typedef struct {
    float cmd[RC_NUM_CMD];  /* normalized [-1..+1], throttle [0..+1] */
    bool  mode_stabilized;  /* true if CH5 > 0 */
} rc_command_t;

/**
 * @brief Initialize RC normalizer
 */
void rc_normalize_init(void);

/**
 * @brief Set trim value for a channel
 * @param channel 0..4
 * @param trim    Trim offset in normalized units [-0.2..+0.2]
 */
void rc_normalize_set_trim(uint8_t channel, float trim);

/**
 * @brief Convert raw SBUS channels to normalized commands
 * @param raw_channels  Raw SBUS 11-bit values (16 channels)
 * @param out           Output normalized commands
 */
void rc_normalize_update(const uint16_t *raw_channels, rc_command_t *out);

#endif /* RC_NORMALIZE_H */
