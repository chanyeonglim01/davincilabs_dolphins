/**
 * @file failsafe.c
 * @brief Failsafe manager implementation
 *
 * Monitors RC and IMU data freshness.
 * On timeout: sets servos to neutral, resets PID integrators.
 */
#include "failsafe.h"
#include "stm32g4xx_hal.h"

/* ---- Private ----------------------------------------------------------- */

static failsafe_state_t state;

/* ---- Public API -------------------------------------------------------- */

void failsafe_init(void)
{
    state = FAILSAFE_RC_LOST; /* assume lost until first frame received */
}

void failsafe_update(uint32_t rc_last_tick, uint32_t imu_last_tick)
{
    uint32_t now = HAL_GetTick();
    bool rc_ok  = (rc_last_tick  != 0) && ((now - rc_last_tick)  < FAILSAFE_RC_TIMEOUT_MS);
    bool imu_ok = (imu_last_tick != 0) && ((now - imu_last_tick) < FAILSAFE_IMU_TIMEOUT_MS);

    if (rc_ok && imu_ok) {
        state = FAILSAFE_OK;
    } else if (!rc_ok && imu_ok) {
        state = FAILSAFE_RC_LOST;
    } else if (rc_ok && !imu_ok) {
        state = FAILSAFE_IMU_LOST;
    } else {
        state = FAILSAFE_BOTH_LOST;
    }
}

failsafe_state_t failsafe_get_state(void)
{
    return state;
}

bool failsafe_is_ok(void)
{
    return (state == FAILSAFE_OK);
}
