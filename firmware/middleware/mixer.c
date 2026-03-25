/**
 * @file mixer.c
 * @brief Servo mixer implementation
 *
 * Pectoral fins use differential mixing:
 *   pec_L = pitch + roll
 *   pec_R = pitch - roll
 * This creates roll moment via asymmetric fin deflection
 * and pitch moment via symmetric deflection.
 */
#include "mixer.h"

/* ---- Private ----------------------------------------------------------- */

static inline float clamp_f(float val, float lo, float hi)
{
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/* ---- Public API -------------------------------------------------------- */

void mixer_manual(float pitch, float roll, float yaw, float throttle,
                  mixer_output_t *out)
{
    /*
     * Tail vertical:  direct pitch command, scaled by throttle presence
     * Tail horizontal: direct yaw command
     * Pectoral L/R:   differential pitch +/- roll
     */
    out->tail_vert = pitch;
    out->tail_horz = yaw;
    out->pec_left  = pitch + roll;
    out->pec_right = pitch - roll;

    /* Throttle -> tail oscillation: freq = throttle * 3 Hz, amp fixed */
    out->tail_freq = throttle * 3.0f;   /* 0~1 -> 0~3 Hz */
    out->tail_amp  = 0.52f;             /* ~30 deg fixed amplitude */

    mixer_saturate(out);
}

void mixer_stabilized(float pitch_cmd, float roll_cmd, float yaw_cmd,
                      float throttle, mixer_output_t *out)
{
    /* Same mixing structure as manual, but inputs from PID */
    out->tail_vert = pitch_cmd;
    out->tail_horz = yaw_cmd;
    out->pec_left  = pitch_cmd + roll_cmd;
    out->pec_right = pitch_cmd - roll_cmd;

    /* Throttle -> tail oscillation: freq = throttle * 3 Hz, amp fixed */
    out->tail_freq = throttle * 3.0f;
    out->tail_amp  = 0.52f;

    mixer_saturate(out);
}

void mixer_neutral(mixer_output_t *out)
{
    out->tail_vert = 0.0f;
    out->tail_horz = 0.0f;
    out->pec_left  = 0.0f;
    out->pec_right = 0.0f;
    out->tail_freq = 0.0f;
    out->tail_amp  = 0.0f;
}

void mixer_saturate(mixer_output_t *out)
{
    out->tail_vert = clamp_f(out->tail_vert, -1.0f, 1.0f);
    out->tail_horz = clamp_f(out->tail_horz, -1.0f, 1.0f);
    out->pec_left  = clamp_f(out->pec_left,  -1.0f, 1.0f);
    out->pec_right = clamp_f(out->pec_right, -1.0f, 1.0f);
}
