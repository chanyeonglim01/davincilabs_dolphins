/**
 * @file power.c
 * @brief Battery voltage ADC monitoring implementation
 *
 * ADC1, single conversion, polled mode.
 * Battery via voltage divider to PA2 (ADC1_IN3).
 */
#include "power.h"
#include "stm32g4xx_hal.h"

/* ---- Private ----------------------------------------------------------- */

static ADC_HandleTypeDef hadc;
static power_data_t power_data;

static uint8_t voltage_to_percent(float v)
{
    /* Simple linear approximation for 1S LiPo */
    if (v >= BATT_FULL_V)     return 100;
    if (v <= BATT_CRITICAL_V) return 0;
    float range = BATT_FULL_V - BATT_CRITICAL_V;
    return (uint8_t)((v - BATT_CRITICAL_V) / range * 100.0f);
}

/* ---- Public API -------------------------------------------------------- */

void power_init(void)
{
    __HAL_RCC_ADC12_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();

    /* PA2 as analog input (ADC1_IN3) */
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin  = GPIO_PIN_2;
    gpio.Mode = GPIO_MODE_ANALOG;
    gpio.Pull = GPIO_NOPULL;
    HAL_GPIO_Init(GPIOA, &gpio);

    hadc.Instance                   = ADC1;
    hadc.Init.ClockPrescaler        = ADC_CLOCK_ASYNC_DIV4;
    hadc.Init.Resolution            = ADC_RESOLUTION_12B;
    hadc.Init.DataAlign             = ADC_DATAALIGN_RIGHT;
    hadc.Init.ScanConvMode          = ADC_SCAN_DISABLE;
    hadc.Init.EOCSelection          = ADC_EOC_SINGLE_CONV;
    hadc.Init.ContinuousConvMode    = DISABLE;
    hadc.Init.NbrOfConversion       = 1;
    hadc.Init.ExternalTrigConv      = ADC_SOFTWARE_START;
    hadc.Init.ExternalTrigConvEdge  = ADC_EXTERNALTRIGCONVEDGE_NONE;
    HAL_ADC_Init(&hadc);

    ADC_ChannelConfTypeDef ch = {0};
    ch.Channel      = ADC_CHANNEL_3;
    ch.Rank         = ADC_REGULAR_RANK_1;
    ch.SamplingTime = ADC_SAMPLETIME_247CYCLES_5;
    ch.SingleDiff   = ADC_SINGLE_ENDED;
    ch.OffsetNumber = ADC_OFFSET_NONE;
    HAL_ADC_ConfigChannel(&hadc, &ch);

    /* Calibrate */
    HAL_ADCEx_Calibration_Start(&hadc, ADC_SINGLE_ENDED);

    power_data.voltage = BATT_NOMINAL_V;
    power_data.percent = 50;
}

void power_read(void)
{
    HAL_ADC_Start(&hadc);
    if (HAL_ADC_PollForConversion(&hadc, 5) == HAL_OK) {
        uint32_t raw = HAL_ADC_GetValue(&hadc);
        float adc_v = (float)raw * ADC_VREF / (float)ADC_RESOLUTION;
        power_data.voltage = adc_v * BATT_VDIV_RATIO;
    }
    HAL_ADC_Stop(&hadc);

    power_data.percent     = voltage_to_percent(power_data.voltage);
    power_data.low_warning = (power_data.voltage < BATT_LOW_V);
    power_data.critical    = (power_data.voltage < BATT_CRITICAL_V);
    power_data.timestamp   = HAL_GetTick();
}

const power_data_t* power_get_data(void)
{
    return &power_data;
}
