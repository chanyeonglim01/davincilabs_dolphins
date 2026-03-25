/**
 * @file control_task.h
 * @brief 100Hz main control loop
 *
 * Orchestrates: SBUS -> RC normalize -> IMU -> Attitude estimation
 *              -> Mode select -> PID/Manual -> Mixer -> Servo output
 */
#ifndef CONTROL_TASK_H
#define CONTROL_TASK_H

#include <stdint.h>

/**
 * @brief Initialize all subsystems for control task
 */
void control_task_init(void);

/**
 * @brief Run one iteration of the 100Hz control loop
 * Called from TIM6 ISR or main loop with timing gate
 */
void control_task_run(void);

/**
 * @brief Get loop counter (for telemetry/debug)
 */
uint32_t control_task_get_loop_count(void);

#endif /* CONTROL_TASK_H */
