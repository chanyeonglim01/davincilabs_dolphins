/**
 * @file control_task.c
 * @brief 100Hz main control loop implementation
 *
 * Sequence per PLAN.md 2.5:
 *  1. SBUS read (DMA, just check for new frame)
 *  2. RC normalize + deadband + trim
 *  3. RC valid check (100ms timeout)
 *  4. IMU read (accel + gyro + mag)
 *  5. Attitude estimation (Madgwick + mag)
 *  6. Mode select (CH5)
 *  7. Controller (Manual or Stabilized PID)
 *  8. Mixer + saturation
 *  9. Servo PWM output
 */
#include "control_task.h"

#include "drivers/sbus_rx.h"
#include "drivers/imu.h"
#include "drivers/servo_pwm.h"
#include "drivers/power.h"

#include "middleware/att_estimator.h"
#include "middleware/rc_normalize.h"
#include "middleware/mixer.h"
#include "middleware/failsafe.h"
#include "middleware/param.h"

#include "stm32g4xx_hal.h"
#include <math.h>
#include <string.h>

/* ================================================================
 * Manual PID implementation (pre-Simulink code generation)
 * Cascade: Outer angle P -> Inner rate PID
 * ================================================================ */

typedef struct {
    float kp, ki, kd;
    float integral;
    float prev_error;
    float output;
} pid_state_t;

typedef struct {
    float outer_kp;         /* angle -> rate command */
    pid_state_t inner;      /* rate PID */
} cascade_pid_t;

static cascade_pid_t pid_roll;
static cascade_pid_t pid_pitch;
static cascade_pid_t pid_yaw;

static void pid_reset(pid_state_t *pid)
{
    pid->integral   = 0.0f;
    pid->prev_error = 0.0f;
    pid->output     = 0.0f;
}

static float pid_update(pid_state_t *pid, float error, float dt)
{
    /* Proportional */
    float p_term = pid->kp * error;

    /* Integral with anti-windup */
    pid->integral += error * dt;
    if (pid->integral > PARAM_PID_ITERM_MAX)  pid->integral = PARAM_PID_ITERM_MAX;
    if (pid->integral < PARAM_PID_ITERM_MIN)  pid->integral = PARAM_PID_ITERM_MIN;
    float i_term = pid->ki * pid->integral;

    /* Derivative (on error) */
    float d_term = pid->kd * (error - pid->prev_error) / dt;
    pid->prev_error = error;

    /* Total output with saturation */
    pid->output = p_term + i_term + d_term;
    if (pid->output > PARAM_PID_OUTPUT_MAX) pid->output = PARAM_PID_OUTPUT_MAX;
    if (pid->output < PARAM_PID_OUTPUT_MIN) pid->output = PARAM_PID_OUTPUT_MIN;

    return pid->output;
}

static float cascade_update(cascade_pid_t *cas, float angle_cmd, float angle,
                            float rate, float dt)
{
    /* Outer loop: angle error -> rate command */
    float angle_error = angle_cmd - angle;
    float rate_cmd = cas->outer_kp * angle_error;

    /* Saturate rate command */
    if (rate_cmd >  PARAM_RATE_CMD_MAX) rate_cmd =  PARAM_RATE_CMD_MAX;
    if (rate_cmd < -PARAM_RATE_CMD_MAX) rate_cmd = -PARAM_RATE_CMD_MAX;

    /* Inner loop: rate error -> actuator command */
    float rate_error = rate_cmd - rate;
    return pid_update(&cas->inner, rate_error, dt);
}

static void cascade_reset(cascade_pid_t *cas)
{
    pid_reset(&cas->inner);
}

static void pid_init_all(void)
{
    /* Roll */
    pid_roll.outer_kp    = PARAM_ROLL_OUTER_P;
    pid_roll.inner.kp    = PARAM_ROLL_INNER_P;
    pid_roll.inner.ki    = PARAM_ROLL_INNER_I;
    pid_roll.inner.kd    = PARAM_ROLL_INNER_D;
    cascade_reset(&pid_roll);

    /* Pitch */
    pid_pitch.outer_kp   = PARAM_PITCH_OUTER_P;
    pid_pitch.inner.kp   = PARAM_PITCH_INNER_P;
    pid_pitch.inner.ki   = PARAM_PITCH_INNER_I;
    pid_pitch.inner.kd   = PARAM_PITCH_INNER_D;
    cascade_reset(&pid_pitch);

    /* Yaw */
    pid_yaw.outer_kp     = PARAM_YAW_OUTER_P;
    pid_yaw.inner.kp     = PARAM_YAW_INNER_P;
    pid_yaw.inner.ki     = PARAM_YAW_INNER_I;
    pid_yaw.inner.kd     = PARAM_YAW_INNER_D;
    cascade_reset(&pid_yaw);
}

/* ================================================================
 * Control task state
 * ================================================================ */

static rc_command_t   rc_cmd;
static mixer_output_t mixer_out;
static uint32_t       loop_count;
static uint32_t       power_divider; /* read battery every 10 loops = 10Hz */

/* ---- Public API -------------------------------------------------------- */

void control_task_init(void)
{
    /* Initialize drivers */
    sbus_rx_init();
    imu_init();
    servo_pwm_init();
    power_init();

    /* Initialize middleware */
    att_estimator_init(PARAM_SAMPLE_FREQ_HZ, PARAM_MADGWICK_BETA);
    rc_normalize_init();
    failsafe_init();

    /* Initialize PID controllers */
    pid_init_all();

    /* Start with neutral servos */
    servo_pwm_set_neutral();

    loop_count    = 0;
    power_divider = 0;
}

void control_task_run(void)
{
    loop_count++;

    /* ---- 1. SBUS: process DMA data ---- */
    sbus_rx_process();
    const sbus_data_t *sbus = sbus_rx_get_data();

    /* ---- 2. RC normalize + deadband + trim ---- */
    rc_normalize_update(sbus->channels, &rc_cmd);

    /* ---- 3. RC valid check ---- */
    /* (handled by failsafe below) */

    /* ---- 4. IMU read ---- */
    imu_read();
    const imu_data_t *imu = imu_get_data();

    /* ---- 5. Attitude estimation ---- */
    if (imu->valid) {
        att_estimator_update(
            imu->accel[0], imu->accel[1], imu->accel[2],
            imu->gyro[0],  imu->gyro[1],  imu->gyro[2],
            imu->mag[0],   imu->mag[1],   imu->mag[2]);
    }
    const attitude_t *att = att_estimator_get();

    /* ---- Failsafe update ---- */
    failsafe_update(sbus->last_valid_tick, imu->timestamp);

    /* ---- 6-7. Mode select + Controller ---- */
    if (!failsafe_is_ok()) {
        /* FAILSAFE: neutral servos + PID reset */
        mixer_neutral(&mixer_out);
        cascade_reset(&pid_roll);
        cascade_reset(&pid_pitch);
        cascade_reset(&pid_yaw);
        att_estimator_reset();
    }
    else if (!rc_cmd.mode_stabilized) {
        /* MANUAL MODE: RC -> mixer directly */
        mixer_manual(rc_cmd.cmd[RC_CH_PITCH],
                     rc_cmd.cmd[RC_CH_ROLL],
                     rc_cmd.cmd[RC_CH_YAW],
                     rc_cmd.cmd[RC_CH_THROTTLE],
                     &mixer_out);

        /* Reset PID integrators when in manual */
        cascade_reset(&pid_roll);
        cascade_reset(&pid_pitch);
        cascade_reset(&pid_yaw);
    }
    else {
        /* STABILIZED MODE: cascade PID */
        float dt = PARAM_DT;

        /* RC commands as angle setpoints (scaled to radians) */
        float roll_sp  = rc_cmd.cmd[RC_CH_ROLL]  * 0.5f; /* max +-30 deg ~ 0.5 rad */
        float pitch_sp = rc_cmd.cmd[RC_CH_PITCH] * 0.3f; /* max +-17 deg ~ 0.3 rad */
        float yaw_sp   = rc_cmd.cmd[RC_CH_YAW]   * 0.5f; /* max +-30 deg ~ 0.5 rad */

        float roll_out  = cascade_update(&pid_roll,  roll_sp,  att->roll,
                                         att->roll_rate,  dt);
        float pitch_out = cascade_update(&pid_pitch, pitch_sp, att->pitch,
                                         att->pitch_rate, dt);
        float yaw_out   = cascade_update(&pid_yaw,   yaw_sp,  att->yaw,
                                         att->yaw_rate,   dt);

        mixer_stabilized(pitch_out, roll_out, yaw_out,
                         rc_cmd.cmd[RC_CH_THROTTLE],
                         &mixer_out);
    }

    /* ---- 8-9. Servo PWM output ---- */
    servo_pwm_set_normalized(SERVO_CH_TAIL_VERT, mixer_out.tail_vert);
    servo_pwm_set_normalized(SERVO_CH_TAIL_HORZ, mixer_out.tail_horz);
    servo_pwm_set_normalized(SERVO_CH_PEC_LEFT,  mixer_out.pec_left);
    servo_pwm_set_normalized(SERVO_CH_PEC_RIGHT, mixer_out.pec_right);

    /* ---- 10. Battery monitoring (10Hz) ---- */
    power_divider++;
    if (power_divider >= 10) {
        power_divider = 0;
        power_read();
    }
}

uint32_t control_task_get_loop_count(void)
{
    return loop_count;
}
