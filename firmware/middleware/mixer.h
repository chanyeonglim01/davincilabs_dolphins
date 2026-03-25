/**
 * @file mixer.h
 * @brief Servo mixer for dolphin drone
 *
 * Maps control commands to servo outputs:
 * - Tail vertical:  pitch command (up/down swimming)
 * - Tail horizontal: yaw command (left/right steering)
 * - Pectoral L: pitch + roll (differential)
 * - Pectoral R: pitch - roll (differential)
 */
#ifndef MIXER_H
#define MIXER_H

typedef struct {
    float tail_vert;   /* tail vertical servo  [-1..+1] */
    float tail_horz;   /* tail horizontal servo [-1..+1] */
    float pec_left;    /* pectoral left  [-1..+1] */
    float pec_right;   /* pectoral right [-1..+1] */
} mixer_output_t;

/**
 * @brief Manual mixer: RC commands direct to servos
 * @param pitch   Pitch command [-1..+1]
 * @param roll    Roll command  [-1..+1]
 * @param yaw     Yaw command   [-1..+1]
 * @param throttle Throttle [0..+1] (tail frequency, mapped to amplitude)
 * @param out     Mixer output
 */
void mixer_manual(float pitch, float roll, float yaw, float throttle,
                  mixer_output_t *out);

/**
 * @brief Stabilized mixer: PID outputs to servos
 * Same mixing logic but inputs come from PID controller
 */
void mixer_stabilized(float pitch_cmd, float roll_cmd, float yaw_cmd,
                      float throttle, mixer_output_t *out);

/**
 * @brief Set all mixer outputs to neutral (zero)
 */
void mixer_neutral(mixer_output_t *out);

/**
 * @brief Apply saturation limits to mixer output
 */
void mixer_saturate(mixer_output_t *out);

#endif /* MIXER_H */
