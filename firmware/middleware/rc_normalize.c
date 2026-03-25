/**
 * @file rc_normalize.c
 * @brief SBUS to normalized RC command conversion
 *
 * Maps raw SBUS [172..1811] to [-1.0..+1.0] with deadband and trim.
 * Throttle channel maps to [0..+1].
 */
#include "rc_normalize.h"
#include "drivers/sbus_rx.h"

/* ---- Private ----------------------------------------------------------- */

static float trim_values[RC_NUM_CMD];

/**
 * Map raw SBUS value to [-1.0, +1.0]
 */
static float sbus_to_normalized(uint16_t raw)
{
    float center = (float)SBUS_RAW_CENTER;
    float range  = (float)(SBUS_RAW_MAX - SBUS_RAW_CENTER);
    float norm   = ((float)raw - center) / range;

    /* Clamp */
    if (norm >  1.0f) norm =  1.0f;
    if (norm < -1.0f) norm = -1.0f;

    return norm;
}

/**
 * Map raw SBUS value to [0.0, +1.0] for throttle
 */
static float sbus_to_throttle(uint16_t raw)
{
    float norm = ((float)raw - (float)SBUS_RAW_MIN) /
                 ((float)SBUS_RAW_MAX - (float)SBUS_RAW_MIN);
    if (norm > 1.0f) norm = 1.0f;
    if (norm < 0.0f) norm = 0.0f;
    return norm;
}

/**
 * Apply deadband around zero
 */
static float apply_deadband(float val, float db)
{
    if (val > db) {
        return (val - db) / (1.0f - db);
    } else if (val < -db) {
        return (val + db) / (1.0f - db);
    }
    return 0.0f;
}

/* ---- Public API -------------------------------------------------------- */

void rc_normalize_init(void)
{
    for (int i = 0; i < RC_NUM_CMD; i++) {
        trim_values[i] = 0.0f;
    }
}

void rc_normalize_set_trim(uint8_t channel, float trim)
{
    if (channel < RC_NUM_CMD) {
        if (trim >  0.2f) trim =  0.2f;
        if (trim < -0.2f) trim = -0.2f;
        trim_values[channel] = trim;
    }
}

void rc_normalize_update(const uint16_t *raw_channels, rc_command_t *out)
{
    /* Roll, Pitch, Yaw: symmetric [-1..+1] */
    out->cmd[RC_CH_ROLL]  = apply_deadband(
        sbus_to_normalized(raw_channels[RC_CH_ROLL])  + trim_values[RC_CH_ROLL],
        RC_DEADBAND);

    out->cmd[RC_CH_PITCH] = apply_deadband(
        sbus_to_normalized(raw_channels[RC_CH_PITCH]) + trim_values[RC_CH_PITCH],
        RC_DEADBAND);

    out->cmd[RC_CH_YAW]   = apply_deadband(
        sbus_to_normalized(raw_channels[RC_CH_YAW])   + trim_values[RC_CH_YAW],
        RC_DEADBAND);

    /* Throttle: [0..+1] */
    out->cmd[RC_CH_THROTTLE] = sbus_to_throttle(raw_channels[RC_CH_THROTTLE])
                               + trim_values[RC_CH_THROTTLE];
    if (out->cmd[RC_CH_THROTTLE] > 1.0f) out->cmd[RC_CH_THROTTLE] = 1.0f;
    if (out->cmd[RC_CH_THROTTLE] < 0.0f) out->cmd[RC_CH_THROTTLE] = 0.0f;

    /* Mode switch: CH5 */
    float mode_raw = sbus_to_normalized(raw_channels[RC_CH_MODE]);
    out->cmd[RC_CH_MODE]    = mode_raw;
    out->mode_stabilized    = (mode_raw > 0.0f);
}
