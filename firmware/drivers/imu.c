/**
 * @file imu.c
 * @brief ICM-20948 9-axis IMU driver implementation (I2C1)
 *
 * Register bank switching for ICM-20948.
 * Magnetometer AK09916 accessed via ICM-20948's internal I2C master.
 */
#include "imu.h"
#include "stm32g4xx_hal.h"
#include <math.h>
#include <string.h>

/* ---- ICM-20948 Register Definitions ------------------------------------ */

/* Bank 0 */
#define REG_BANK_SEL        0x7F
#define REG_WHO_AM_I        0x00
#define REG_USER_CTRL       0x03
#define REG_PWR_MGMT_1      0x06
#define REG_PWR_MGMT_2      0x07
#define REG_ACCEL_XOUT_H    0x2D
#define REG_GYRO_XOUT_H     0x33
#define REG_EXT_SLV_SENS_DATA_00 0x3B

/* Bank 2 */
#define REG_GYRO_CONFIG_1   0x01
#define REG_ACCEL_CONFIG    0x14

/* Bank 3 (I2C master) */
#define REG_I2C_MST_CTRL    0x01
#define REG_I2C_SLV0_ADDR   0x03
#define REG_I2C_SLV0_REG    0x04
#define REG_I2C_SLV0_CTRL   0x05

/* AK09916 registers */
#define AK_WIA2             0x01
#define AK_CNTL2            0x31
#define AK_ST1              0x10
#define AK_HXL              0x11

#define ICM20948_WHO_AM_I_VAL  0xEA
#define AK09916_WHO_AM_I_VAL   0x09

/* Scale factors */
#define ACCEL_SCALE_4G      (4.0f * 9.80665f / 32768.0f)   /* m/s^2 per LSB */
#define GYRO_SCALE_500DPS   (500.0f * (float)M_PI / (180.0f * 32768.0f)) /* rad/s per LSB */
#define MAG_SCALE_UT        0.15f   /* uT per LSB (AK09916) */

/* ---- Private ----------------------------------------------------------- */

static I2C_HandleTypeDef hi2c_imu;
static imu_data_t imu_data;

static HAL_StatusTypeDef imu_write_reg(uint8_t reg, uint8_t val)
{
    return HAL_I2C_Mem_Write(&hi2c_imu, ICM20948_ADDR, reg,
                             I2C_MEMADD_SIZE_8BIT, &val, 1, 10);
}

static HAL_StatusTypeDef imu_read_regs(uint8_t reg, uint8_t *buf, uint16_t len)
{
    return HAL_I2C_Mem_Read(&hi2c_imu, ICM20948_ADDR, reg,
                            I2C_MEMADD_SIZE_8BIT, buf, len, 10);
}

static void imu_select_bank(uint8_t bank)
{
    imu_write_reg(REG_BANK_SEL, (bank & 0x03) << 4);
}

/* ---- I2C1 Low-level init ----------------------------------------------- */

static bool imu_i2c_init(void)
{
    __HAL_RCC_I2C1_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();

    /* I2C1: SCL=PB6, SDA=PB7, AF4 */
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin       = GPIO_PIN_6 | GPIO_PIN_7;
    gpio.Mode      = GPIO_MODE_AF_OD;
    gpio.Pull      = GPIO_PULLUP;
    gpio.Speed     = GPIO_SPEED_FREQ_HIGH;
    gpio.Alternate = GPIO_AF4_I2C1;
    HAL_GPIO_Init(GPIOB, &gpio);

    hi2c_imu.Instance             = I2C1;
    hi2c_imu.Init.Timing          = 0x10707DBC; /* 400kHz @ 170MHz PCLK */
    hi2c_imu.Init.OwnAddress1     = 0;
    hi2c_imu.Init.AddressingMode  = I2C_ADDRESSINGMODE_7BIT;
    hi2c_imu.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
    hi2c_imu.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
    hi2c_imu.Init.NoStretchMode   = I2C_NOSTRETCH_DISABLE;

    return HAL_I2C_Init(&hi2c_imu) == HAL_OK;
}

/* ---- Setup AK09916 magnetometer via I2C master ------------------------- */

static bool imu_setup_mag(void)
{
    /* Bank 3: I2C master config */
    imu_select_bank(3);

    /* I2C master clock = 400kHz */
    imu_write_reg(REG_I2C_MST_CTRL, 0x07);

    /* First, read AK09916 WHO_AM_I (WIA2 = 0x01) to verify presence */
    imu_write_reg(REG_I2C_SLV0_ADDR, AK09916_ADDR | 0x80); /* read */
    imu_write_reg(REG_I2C_SLV0_REG,  AK_WIA2);
    imu_write_reg(REG_I2C_SLV0_CTRL, 0x81); /* enable, 1 byte */

    imu_select_bank(0);

    /* Enable I2C master temporarily to perform read */
    uint8_t user_ctrl;
    imu_read_regs(REG_USER_CTRL, &user_ctrl, 1);
    user_ctrl |= 0x20; /* I2C_MST_EN */
    imu_write_reg(REG_USER_CTRL, user_ctrl);

    HAL_Delay(10);

    /* Read WHO_AM_I result from EXT_SLV_SENS_DATA_00 */
    uint8_t mag_wia = 0;
    imu_read_regs(REG_EXT_SLV_SENS_DATA_00, &mag_wia, 1);
    if (mag_wia != AK09916_WHO_AM_I_VAL) return false;

    /* Bank 3: Write to AK09916 CNTL2: continuous mode 4 (100Hz) */
    imu_select_bank(3);
    imu_write_reg(REG_I2C_SLV0_ADDR, AK09916_ADDR);
    imu_write_reg(REG_I2C_SLV0_REG,  AK_CNTL2);
    uint8_t cntl2_val = 0x08; /* continuous mode 4 = 100Hz */
    imu_write_reg(0x06, cntl2_val); /* SLV0_DO */
    imu_write_reg(REG_I2C_SLV0_CTRL, 0x81); /* enable, 1 byte */

    HAL_Delay(10);

    /* Set SLV0 to read ST1 + 8 bytes from AK09916 (ST1 + HXL..HZH + ST2)
     * Reading ST1 first allows data-ready check before using mag data */
    imu_write_reg(REG_I2C_SLV0_ADDR, AK09916_ADDR | 0x80); /* read */
    imu_write_reg(REG_I2C_SLV0_REG,  AK_ST1);
    imu_write_reg(REG_I2C_SLV0_CTRL, 0x89); /* enable, 9 bytes (ST1+6mag+ST2) */

    imu_select_bank(0);
    return true;
}

/* ---- Public API -------------------------------------------------------- */

bool imu_init(void)
{
    memset(&imu_data, 0, sizeof(imu_data));

    if (!imu_i2c_init()) return false;

    /* Bank 0: check WHO_AM_I */
    imu_select_bank(0);
    uint8_t who = 0;
    imu_read_regs(REG_WHO_AM_I, &who, 1);
    if (who != ICM20948_WHO_AM_I_VAL) return false;

    /* Reset */
    imu_write_reg(REG_PWR_MGMT_1, 0x80);
    HAL_Delay(100);

    /* Wake up, auto clock */
    imu_write_reg(REG_PWR_MGMT_1, 0x01);
    HAL_Delay(30);

    /* Enable all axes */
    imu_write_reg(REG_PWR_MGMT_2, 0x00);

    /* Bank 2: gyro config = +-500dps, DLPF 51Hz */
    imu_select_bank(2);
    imu_write_reg(REG_GYRO_CONFIG_1, 0x0B); /* +-500dps, DLPF_CFG=3 */

    /* Accel config = +-4g, DLPF 50Hz */
    imu_write_reg(REG_ACCEL_CONFIG, 0x0B); /* +-4g, DLPF_CFG=3 */

    /* Setup magnetometer (verify AK09916 WHO_AM_I) */
    if (!imu_setup_mag()) return false;

    imu_data.valid = true;
    return true;
}

void imu_read(void)
{
    uint8_t buf[20];

    imu_select_bank(0);

    /* Read accel (6) + gyro (6) = 12 bytes starting from ACCEL_XOUT_H */
    if (imu_read_regs(REG_ACCEL_XOUT_H, buf, 12) != HAL_OK) {
        imu_data.valid = false;
        return;
    }

    /* Parse accelerometer (big-endian) */
    int16_t raw_ax = (int16_t)(buf[0]  << 8 | buf[1]);
    int16_t raw_ay = (int16_t)(buf[2]  << 8 | buf[3]);
    int16_t raw_az = (int16_t)(buf[4]  << 8 | buf[5]);

    /* Parse gyroscope (big-endian) */
    int16_t raw_gx = (int16_t)(buf[6]  << 8 | buf[7]);
    int16_t raw_gy = (int16_t)(buf[8]  << 8 | buf[9]);
    int16_t raw_gz = (int16_t)(buf[10] << 8 | buf[11]);

    imu_data.accel[0] = raw_ax * ACCEL_SCALE_4G;
    imu_data.accel[1] = raw_ay * ACCEL_SCALE_4G;
    imu_data.accel[2] = raw_az * ACCEL_SCALE_4G;

    imu_data.gyro[0] = raw_gx * GYRO_SCALE_500DPS;
    imu_data.gyro[1] = raw_gy * GYRO_SCALE_500DPS;
    imu_data.gyro[2] = raw_gz * GYRO_SCALE_500DPS;

    /* Read magnetometer from EXT_SLV_SENS_DATA (9 bytes: ST1 + 6 mag + ST2)
     * ST1 bit0 (DRDY) must be set for valid data */
    uint8_t mag_buf[9];
    if (imu_read_regs(REG_EXT_SLV_SENS_DATA_00, mag_buf, 9) == HAL_OK) {
        if (mag_buf[0] & 0x01) { /* ST1 DRDY bit */
            int16_t raw_mx = (int16_t)(mag_buf[2] << 8 | mag_buf[1]);
            int16_t raw_my = (int16_t)(mag_buf[4] << 8 | mag_buf[3]);
            int16_t raw_mz = (int16_t)(mag_buf[6] << 8 | mag_buf[5]);

            imu_data.mag[0] = raw_mx * MAG_SCALE_UT;
            imu_data.mag[1] = raw_my * MAG_SCALE_UT;
            imu_data.mag[2] = raw_mz * MAG_SCALE_UT;
        }
        /* If DRDY not set, keep previous mag values (stale but better than zero) */
    }

    imu_data.timestamp = HAL_GetTick();
    imu_data.valid = true;
}

const imu_data_t* imu_get_data(void)
{
    return &imu_data;
}
