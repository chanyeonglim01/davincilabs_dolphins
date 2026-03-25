/**
 * @file servo_pwm.h
 * @brief PWM 4-channel servo output driver
 *
 * 50Hz PWM, 1000-2000us pulse width.
 * CH0: Tail vertical (pitch)
 * CH1: Tail horizontal (yaw)
 * CH2: Pectoral Left
 * CH3: Pectoral Right
 */
#ifndef SERVO_PWM_H
#define SERVO_PWM_H

#include <stdint.h>

#define SERVO_NUM_CHANNELS  4

/* Channel indices */
#define SERVO_CH_TAIL_VERT  0   /* tail up/down */
#define SERVO_CH_TAIL_HORZ  1   /* tail left/right */
#define SERVO_CH_PEC_LEFT   2   /* pectoral left */
#define SERVO_CH_PEC_RIGHT  3   /* pectoral right */

/* Pulse width limits (microseconds) */
#define SERVO_PULSE_MIN     1000
#define SERVO_PULSE_CENTER  1500
#define SERVO_PULSE_MAX     2000

/**
 * @brief Initialize PWM outputs on TIM2/TIM3 for 4 servos
 * 50Hz, 20ms period, 1000-2000us pulse range
 */
void servo_pwm_init(void);

/**
 * @brief Set servo pulse width
 * @param channel 0..3
 * @param pulse_us Pulse width in microseconds [1000..2000]
 */
void servo_pwm_set_pulse(uint8_t channel, uint16_t pulse_us);

/**
 * @brief Set servo position from normalized value
 * @param channel 0..3
 * @param value Normalized [-1.0 .. +1.0], 0.0 = center
 */
void servo_pwm_set_normalized(uint8_t channel, float value);

/**
 * @brief Set all servos to neutral (1500us)
 */
void servo_pwm_set_neutral(void);

#endif /* SERVO_PWM_H */
