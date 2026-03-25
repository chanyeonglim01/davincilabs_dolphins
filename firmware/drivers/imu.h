/**
 * @file imu.h
 * @brief ICM-20948 9-axis IMU driver (I2C)
 *
 * Reads accelerometer, gyroscope, and magnetometer (AK09916) data.
 * I2C1 on STM32G431KB.
 */
#ifndef IMU_H
#define IMU_H

#include <stdint.h>
#include <stdbool.h>

/* ICM-20948 I2C address (AD0 = LOW) */
#define ICM20948_ADDR       (0x68 << 1)

/* AK09916 (magnetometer) I2C address via ICM-20948 I2C master */
#define AK09916_ADDR        0x0C

typedef struct {
    float accel[3];     /* m/s^2, body frame [x, y, z] */
    float gyro[3];      /* rad/s, body frame [p, q, r]  */
    float mag[3];       /* uT, body frame [x, y, z]     */
    uint32_t timestamp; /* HAL_GetTick() of last read    */
    bool valid;
} imu_data_t;

/**
 * @brief Initialize ICM-20948 on I2C1
 * Configures accel +-4g, gyro +-500 dps, mag 100Hz continuous
 * @return true on success (WHO_AM_I verified)
 */
bool imu_init(void);

/**
 * @brief Read all 9 axes from IMU
 * Blocking I2C read, call at 100Hz from main loop
 */
void imu_read(void);

/**
 * @brief Get pointer to latest IMU data
 */
const imu_data_t* imu_get_data(void);

#endif /* IMU_H */
