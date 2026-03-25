/**
 * @file failsafe.h
 * @brief Failsafe manager — RC/IMU timeout detection and safe actions
 */
#ifndef FAILSAFE_H
#define FAILSAFE_H

#include <stdint.h>
#include <stdbool.h>

/* Timeout thresholds (ms) */
#define FAILSAFE_RC_TIMEOUT_MS   100
#define FAILSAFE_IMU_TIMEOUT_MS  50

typedef enum {
    FAILSAFE_OK = 0,       /* all good */
    FAILSAFE_RC_LOST,      /* RC signal lost */
    FAILSAFE_IMU_LOST,     /* IMU data stale */
    FAILSAFE_BOTH_LOST     /* both lost */
} failsafe_state_t;

/**
 * @brief Initialize failsafe module
 */
void failsafe_init(void);

/**
 * @brief Update failsafe state (call every loop iteration)
 * @param rc_last_tick   HAL_GetTick() of last valid RC frame
 * @param imu_last_tick  HAL_GetTick() of last valid IMU read
 */
void failsafe_update(uint32_t rc_last_tick, uint32_t imu_last_tick);

/**
 * @brief Get current failsafe state
 */
failsafe_state_t failsafe_get_state(void);

/**
 * @brief Check if system is safe to fly
 * @return true if FAILSAFE_OK
 */
bool failsafe_is_ok(void);

#endif /* FAILSAFE_H */
