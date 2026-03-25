/**
 * @file att_estimator.h
 * @brief Attitude estimator — Madgwick AHRS with magnetometer fusion
 *
 * Outputs roll, pitch, yaw (radians) and angular rates.
 */
#ifndef ATT_ESTIMATOR_H
#define ATT_ESTIMATOR_H

#include <stdint.h>

typedef struct {
    float roll;      /* radians, positive = right wing down */
    float pitch;     /* radians, positive = nose up          */
    float yaw;       /* radians, 0..2*PI, magnetic north=0   */
    float roll_rate; /* rad/s */
    float pitch_rate;/* rad/s */
    float yaw_rate;  /* rad/s */
} attitude_t;

/**
 * @brief Initialize the attitude estimator
 * @param sample_freq  Update rate in Hz (100)
 * @param beta         Madgwick filter gain (default 0.1)
 */
void att_estimator_init(float sample_freq, float beta);

/**
 * @brief Update attitude estimate with 9-axis data
 * @param ax,ay,az  Accelerometer in m/s^2
 * @param gx,gy,gz  Gyroscope in rad/s
 * @param mx,my,mz  Magnetometer in uT
 */
void att_estimator_update(float ax, float ay, float az,
                          float gx, float gy, float gz,
                          float mx, float my, float mz);

/**
 * @brief Update attitude estimate with 6-axis only (no mag)
 * Falls back to IMU-only Madgwick when mag data unavailable
 */
void att_estimator_update_imu(float ax, float ay, float az,
                              float gx, float gy, float gz);

/**
 * @brief Get current attitude estimate
 */
const attitude_t* att_estimator_get(void);

/**
 * @brief Reset quaternion to identity
 */
void att_estimator_reset(void);

#endif /* ATT_ESTIMATOR_H */
