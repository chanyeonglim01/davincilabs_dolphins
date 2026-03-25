/**
 * @file servo_pwm.c
 * @brief PWM 4-channel servo output implementation
 *
 * TIM2 CH1/CH2: Tail servos (PA0, PA1)
 * TIM3 CH1/CH2: Pectoral servos (PA6, PA7)
 * 50Hz PWM, timer clocked at 1MHz (prescaler for 1us resolution)
 */
#include "servo_pwm.h"
#include "stm32g4xx_hal.h"

/* ---- Private ----------------------------------------------------------- */

static TIM_HandleTypeDef htim2;
static TIM_HandleTypeDef htim3;

/* Timer clock = 170 MHz -> prescaler 170-1 = 1 MHz (1us resolution)
 * Period = 20000-1 for 50Hz (20ms) */
#define PWM_PRESCALER   (170 - 1)
#define PWM_PERIOD      (20000 - 1)

static void servo_timer_init(TIM_HandleTypeDef *htim, TIM_TypeDef *instance)
{
    htim->Instance               = instance;
    htim->Init.Prescaler         = PWM_PRESCALER;
    htim->Init.CounterMode       = TIM_COUNTERMODE_UP;
    htim->Init.Period            = PWM_PERIOD;
    htim->Init.ClockDivision     = TIM_CLOCKDIVISION_DIV1;
    htim->Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_ENABLE;
    HAL_TIM_PWM_Init(htim);

    TIM_OC_InitTypeDef oc = {0};
    oc.OCMode     = TIM_OCMODE_PWM1;
    oc.Pulse      = SERVO_PULSE_CENTER;
    oc.OCPolarity = TIM_OCPOLARITY_HIGH;
    oc.OCFastMode = TIM_OCFAST_DISABLE;

    HAL_TIM_PWM_ConfigChannel(htim, &oc, TIM_CHANNEL_1);
    HAL_TIM_PWM_ConfigChannel(htim, &oc, TIM_CHANNEL_2);

    HAL_TIM_PWM_Start(htim, TIM_CHANNEL_1);
    HAL_TIM_PWM_Start(htim, TIM_CHANNEL_2);
}

/* Clamp integer */
static inline uint16_t clamp_u16(uint16_t val, uint16_t lo, uint16_t hi)
{
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/* Clamp float */
static inline float clamp_f(float val, float lo, float hi)
{
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/* ---- Public API -------------------------------------------------------- */

void servo_pwm_init(void)
{
    /* Enable clocks */
    __HAL_RCC_TIM2_CLK_ENABLE();
    __HAL_RCC_TIM3_CLK_ENABLE();
    __HAL_RCC_GPIOA_CLK_ENABLE();

    /* TIM2 CH1=PA0, CH2=PA1 (AF1) */
    GPIO_InitTypeDef gpio = {0};
    gpio.Pin       = GPIO_PIN_0 | GPIO_PIN_1;
    gpio.Mode      = GPIO_MODE_AF_PP;
    gpio.Pull      = GPIO_NOPULL;
    gpio.Speed     = GPIO_SPEED_FREQ_LOW;
    gpio.Alternate = GPIO_AF1_TIM2;
    HAL_GPIO_Init(GPIOA, &gpio);

    /* TIM3 CH1=PA6, CH2=PA7 (AF2) */
    gpio.Pin       = GPIO_PIN_6 | GPIO_PIN_7;
    gpio.Alternate = GPIO_AF2_TIM3;
    HAL_GPIO_Init(GPIOA, &gpio);

    servo_timer_init(&htim2, TIM2);
    servo_timer_init(&htim3, TIM3);
}

void servo_pwm_set_pulse(uint8_t channel, uint16_t pulse_us)
{
    pulse_us = clamp_u16(pulse_us, SERVO_PULSE_MIN, SERVO_PULSE_MAX);

    switch (channel) {
    case SERVO_CH_TAIL_VERT:
        __HAL_TIM_SET_COMPARE(&htim2, TIM_CHANNEL_1, pulse_us);
        break;
    case SERVO_CH_TAIL_HORZ:
        __HAL_TIM_SET_COMPARE(&htim2, TIM_CHANNEL_2, pulse_us);
        break;
    case SERVO_CH_PEC_LEFT:
        __HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_1, pulse_us);
        break;
    case SERVO_CH_PEC_RIGHT:
        __HAL_TIM_SET_COMPARE(&htim3, TIM_CHANNEL_2, pulse_us);
        break;
    default:
        break;
    }
}

void servo_pwm_set_normalized(uint8_t channel, float value)
{
    value = clamp_f(value, -1.0f, 1.0f);
    uint16_t pulse = (uint16_t)(SERVO_PULSE_CENTER + value * 500.0f);
    servo_pwm_set_pulse(channel, pulse);
}

void servo_pwm_set_neutral(void)
{
    for (uint8_t i = 0; i < SERVO_NUM_CHANNELS; i++) {
        servo_pwm_set_pulse(i, SERVO_PULSE_CENTER);
    }
}
