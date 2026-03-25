/**
 * @file power.h
 * @brief Battery voltage ADC monitoring
 *
 * 1S LiPo monitoring via voltage divider + ADC.
 * STM32G431KB ADC1.
 */
#ifndef POWER_H
#define POWER_H

#include <stdint.h>
#include <stdbool.h>

/* Battery thresholds (volts) */
#define BATT_FULL_V         4.20f
#define BATT_NOMINAL_V      3.70f
#define BATT_LOW_V          3.50f
#define BATT_CRITICAL_V     3.30f

/* Voltage divider: R1=10k, R2=10k -> ratio = 0.5 */
#define BATT_VDIV_RATIO     2.0f   /* multiply ADC voltage by this */

/* ADC reference voltage */
#define ADC_VREF            3.3f
#define ADC_RESOLUTION      4096

typedef struct {
    float    voltage;     /* battery voltage in volts */
    uint8_t  percent;     /* estimated SOC 0-100% */
    bool     low_warning;
    bool     critical;
    uint32_t timestamp;
} power_data_t;

/**
 * @brief Initialize ADC1 for battery voltage reading
 * ADC1 IN1 on PA0 (or dedicated pin, depending on PCB)
 */
void power_init(void);

/**
 * @brief Read battery voltage (call at ~10Hz)
 */
void power_read(void);

/**
 * @brief Get pointer to power data
 */
const power_data_t* power_get_data(void);

#endif /* POWER_H */
