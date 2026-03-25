/**
 * @file param.h
 * @brief System parameters — PID gains, limits, and trims
 *
 * All tunable parameters in one place.
 * Confirmed gains from Simulink tuning (PLAN.md 1.2).
 */
#ifndef PARAM_H
#define PARAM_H

/* ================================================================
 * Cascade PID gains
 * Structure: Outer (angle P) -> Inner (rate PID)
 * ================================================================ */

/* --- Roll axis (p) --- */
#define PARAM_ROLL_OUTER_P      1.4f

#define PARAM_ROLL_INNER_P      0.30f
#define PARAM_ROLL_INNER_I      0.01f
#define PARAM_ROLL_INNER_D      0.10f

/* --- Pitch axis (q) --- */
#define PARAM_PITCH_OUTER_P     0.25f

#define PARAM_PITCH_INNER_P     0.20f
#define PARAM_PITCH_INNER_I     0.00f
#define PARAM_PITCH_INNER_D     0.02f

/* --- Yaw axis (r) --- */
#define PARAM_YAW_OUTER_P       1.0f

#define PARAM_YAW_INNER_P       0.20f
#define PARAM_YAW_INNER_I       0.02f
#define PARAM_YAW_INNER_D       0.03f

/* ================================================================
 * PID limits
 * ================================================================ */

/* Inner loop output saturation */
#define PARAM_PID_OUTPUT_MAX    1.0f
#define PARAM_PID_OUTPUT_MIN   -1.0f

/* Integrator anti-windup limits */
#define PARAM_PID_ITERM_MAX     0.3f
#define PARAM_PID_ITERM_MIN    -0.3f

/* Outer loop rate command saturation (rad/s) */
#define PARAM_RATE_CMD_MAX      3.0f   /* ~170 deg/s */

/* ================================================================
 * Attitude estimator
 * ================================================================ */
#define PARAM_MADGWICK_BETA     0.1f
#define PARAM_SAMPLE_FREQ_HZ   100.0f
#define PARAM_DT                (1.0f / PARAM_SAMPLE_FREQ_HZ)

/* ================================================================
 * RC configuration
 * ================================================================ */
#define PARAM_RC_DEADBAND       0.05f
#define PARAM_RC_EXPO           0.0f   /* 0 = linear, future use */

/* ================================================================
 * Servo limits
 * ================================================================ */
#define PARAM_SERVO_TRAVEL_DEG  45.0f  /* max deflection from neutral */

/* ================================================================
 * Failsafe
 * ================================================================ */
#define PARAM_RC_TIMEOUT_MS     100
#define PARAM_IMU_TIMEOUT_MS    50

#endif /* PARAM_H */
