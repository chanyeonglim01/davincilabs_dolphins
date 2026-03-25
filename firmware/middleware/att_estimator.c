/**
 * @file att_estimator.c
 * @brief Madgwick AHRS filter with magnetometer fusion
 *
 * Based on S. Madgwick's open-source implementation.
 * Quaternion representation, Euler output.
 */
#include "att_estimator.h"
#include <math.h>

/* ---- Private ----------------------------------------------------------- */

static float q0 = 1.0f, q1 = 0.0f, q2 = 0.0f, q3 = 0.0f;
static float beta_gain;
static float inv_sample_freq;
static attitude_t attitude;

static float inv_sqrt(float x)
{
    /* Fast inverse square root (sufficient for embedded) */
    if (x <= 0.0f) return 0.0f;
    return 1.0f / sqrtf(x);
}

/* ---- Public API -------------------------------------------------------- */

void att_estimator_init(float sample_freq, float beta)
{
    q0 = 1.0f; q1 = 0.0f; q2 = 0.0f; q3 = 0.0f;
    beta_gain = beta;
    inv_sample_freq = 1.0f / sample_freq;
    attitude.roll  = 0.0f;
    attitude.pitch = 0.0f;
    attitude.yaw   = 0.0f;
}

void att_estimator_update(float ax, float ay, float az,
                          float gx, float gy, float gz,
                          float mx, float my, float mz)
{
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float hx, hy;
    float _2q0mx, _2q0my, _2q0mz, _2q1mx;
    float _2bx, _2bz, _4bx, _4bz;
    float _2q0, _2q1, _2q2, _2q3;
    float _2q0q2, _2q2q3;
    float q0q0, q0q1, q0q2, q0q3;
    float q1q1, q1q2, q1q3;
    float q2q2, q2q3;
    float q3q3;

    /* Rate of change of quaternion from gyroscope */
    qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
    qDot2 = 0.5f * ( q0 * gx + q2 * gz - q3 * gy);
    qDot3 = 0.5f * ( q0 * gy - q1 * gz + q3 * gx);
    qDot4 = 0.5f * ( q0 * gz + q1 * gy - q2 * gx);

    /* Normalise accelerometer measurement */
    recipNorm = inv_sqrt(ax * ax + ay * ay + az * az);
    if (recipNorm == 0.0f) goto integrate;
    ax *= recipNorm;
    ay *= recipNorm;
    az *= recipNorm;

    /* Normalise magnetometer measurement */
    recipNorm = inv_sqrt(mx * mx + my * my + mz * mz);
    if (recipNorm == 0.0f) {
        /* Fall back to IMU-only update */
        att_estimator_update_imu(ax, ay, az, gx, gy, gz);
        return;
    }
    mx *= recipNorm;
    my *= recipNorm;
    mz *= recipNorm;

    /* Auxiliary variables */
    _2q0mx = 2.0f * q0 * mx;
    _2q0my = 2.0f * q0 * my;
    _2q0mz = 2.0f * q0 * mz;
    _2q1mx = 2.0f * q1 * mx;
    _2q0 = 2.0f * q0;
    _2q1 = 2.0f * q1;
    _2q2 = 2.0f * q2;
    _2q3 = 2.0f * q3;
    _2q0q2 = 2.0f * q0 * q2;
    _2q2q3 = 2.0f * q2 * q3;
    q0q0 = q0 * q0;
    q0q1 = q0 * q1;
    q0q2 = q0 * q2;
    q0q3 = q0 * q3;
    q1q1 = q1 * q1;
    q1q2 = q1 * q2;
    q1q3 = q1 * q3;
    q2q2 = q2 * q2;
    q2q3 = q2 * q3;
    q3q3 = q3 * q3;

    /* Reference direction of Earth's magnetic field */
    hx = mx * q0q0 - _2q0my * q3 + _2q0mz * q2 + mx * q1q1
       + _2q1 * my * q2 + _2q1 * mz * q3 - mx * q2q2 - mx * q3q3;
    hy = _2q0mx * q3 + my * q0q0 - _2q0mz * q1 + _2q1mx * q2
       - my * q1q1 + my * q2q2 + _2q2 * mz * q3 - my * q3q3;
    _2bx = sqrtf(hx * hx + hy * hy);
    _2bz = -_2q0mx * q2 + _2q0my * q1 + mz * q0q0 + _2q1mx * q3
          - mz * q1q1 + _2q2 * my * q3 - mz * q2q2 + mz * q3q3;
    _4bx = 2.0f * _2bx;
    _4bz = 2.0f * _2bz;

    /* Gradient descent corrective step */
    s0 = -_2q2 * (2.0f * q1q3 - _2q0q2 - ax)
       + _2q1 * (2.0f * q0q1 + _2q2q3 - ay)
       - _2bz * q2 * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx)
       + (-_2bx * q3 + _2bz * q1) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my)
       + _2bx * q2 * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
    s1 = _2q3 * (2.0f * q1q3 - _2q0q2 - ax)
       + _2q0 * (2.0f * q0q1 + _2q2q3 - ay)
       - 4.0f * q1 * (1 - 2.0f * q1q1 - 2.0f * q2q2 - az)
       + _2bz * q3 * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx)
       + (_2bx * q2 + _2bz * q0) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my)
       + (_2bx * q3 - _4bz * q1) * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
    s2 = -_2q0 * (2.0f * q1q3 - _2q0q2 - ax)
       + _2q3 * (2.0f * q0q1 + _2q2q3 - ay)
       - 4.0f * q2 * (1 - 2.0f * q1q1 - 2.0f * q2q2 - az)
       + (-_4bx * q2 - _2bz * q0) * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx)
       + (_2bx * q1 + _2bz * q3) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my)
       + (_2bx * q0 - _4bz * q2) * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
    s3 = _2q1 * (2.0f * q1q3 - _2q0q2 - ax)
       + _2q2 * (2.0f * q0q1 + _2q2q3 - ay)
       + (-_4bx * q3 + _2bz * q1) * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx)
       + (-_2bx * q0 + _2bz * q2) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my)
       + _2bx * q1 * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);

    /* Normalise step magnitude */
    recipNorm = inv_sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
    s0 *= recipNorm;
    s1 *= recipNorm;
    s2 *= recipNorm;
    s3 *= recipNorm;

    /* Apply feedback step */
    qDot1 -= beta_gain * s0;
    qDot2 -= beta_gain * s1;
    qDot3 -= beta_gain * s2;
    qDot4 -= beta_gain * s3;

integrate:
    /* Integrate rate of change of quaternion */
    q0 += qDot1 * inv_sample_freq;
    q1 += qDot2 * inv_sample_freq;
    q2 += qDot3 * inv_sample_freq;
    q3 += qDot4 * inv_sample_freq;

    /* Normalise quaternion */
    recipNorm = inv_sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    q0 *= recipNorm;
    q1 *= recipNorm;
    q2 *= recipNorm;
    q3 *= recipNorm;

    /* Convert to Euler angles */
    attitude.roll  = atan2f(2.0f * (q0 * q1 + q2 * q3),
                            1.0f - 2.0f * (q1 * q1 + q2 * q2));
    attitude.pitch = asinf(2.0f * (q0 * q2 - q3 * q1));
    attitude.yaw   = atan2f(2.0f * (q0 * q3 + q1 * q2),
                            1.0f - 2.0f * (q2 * q2 + q3 * q3));

    /* Wrap yaw to [0, 2*PI) */
    if (attitude.yaw < 0.0f) attitude.yaw += 2.0f * (float)M_PI;

    /* Store angular rates */
    attitude.roll_rate  = gx;
    attitude.pitch_rate = gy;
    attitude.yaw_rate   = gz;
}

void att_estimator_update_imu(float ax, float ay, float az,
                              float gx, float gy, float gz)
{
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float _2q0, _2q1, _2q2, _2q3, _4q0, _4q1, _4q2;
    float _8q1, _8q2;
    float q0q0, q1q1, q2q2, q3q3;

    /* Rate of change of quaternion from gyroscope */
    qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
    qDot2 = 0.5f * ( q0 * gx + q2 * gz - q3 * gy);
    qDot3 = 0.5f * ( q0 * gy - q1 * gz + q3 * gx);
    qDot4 = 0.5f * ( q0 * gz + q1 * gy - q2 * gx);

    recipNorm = inv_sqrt(ax * ax + ay * ay + az * az);
    if (recipNorm == 0.0f) goto integrate_imu;
    ax *= recipNorm;
    ay *= recipNorm;
    az *= recipNorm;

    _2q0 = 2.0f * q0;  _2q1 = 2.0f * q1;
    _2q2 = 2.0f * q2;  _2q3 = 2.0f * q3;
    _4q0 = 4.0f * q0;  _4q1 = 4.0f * q1;
    _4q2 = 4.0f * q2;
    _8q1 = 8.0f * q1;  _8q2 = 8.0f * q2;
    q0q0 = q0 * q0;    q1q1 = q1 * q1;
    q2q2 = q2 * q2;    q3q3 = q3 * q3;

    s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
    s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * q1 - _2q0 * ay
       - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
    s2 = 4.0f * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay
       - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
    s3 = 4.0f * q1q1 * q3 - _2q1 * ax + 4.0f * q2q2 * q3 - _2q2 * ay;

    recipNorm = inv_sqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
    s0 *= recipNorm;  s1 *= recipNorm;
    s2 *= recipNorm;  s3 *= recipNorm;

    qDot1 -= beta_gain * s0;
    qDot2 -= beta_gain * s1;
    qDot3 -= beta_gain * s2;
    qDot4 -= beta_gain * s3;

integrate_imu:
    q0 += qDot1 * inv_sample_freq;
    q1 += qDot2 * inv_sample_freq;
    q2 += qDot3 * inv_sample_freq;
    q3 += qDot4 * inv_sample_freq;

    recipNorm = inv_sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
    q0 *= recipNorm;  q1 *= recipNorm;
    q2 *= recipNorm;  q3 *= recipNorm;

    attitude.roll  = atan2f(2.0f * (q0 * q1 + q2 * q3),
                            1.0f - 2.0f * (q1 * q1 + q2 * q2));
    attitude.pitch = asinf(2.0f * (q0 * q2 - q3 * q1));
    attitude.yaw   = atan2f(2.0f * (q0 * q3 + q1 * q2),
                            1.0f - 2.0f * (q2 * q2 + q3 * q3));
    if (attitude.yaw < 0.0f) attitude.yaw += 2.0f * (float)M_PI;

    attitude.roll_rate  = gx;
    attitude.pitch_rate = gy;
    attitude.yaw_rate   = gz;
}

const attitude_t* att_estimator_get(void)
{
    return &attitude;
}

void att_estimator_reset(void)
{
    q0 = 1.0f; q1 = 0.0f; q2 = 0.0f; q3 = 0.0f;
    attitude.roll  = 0.0f;
    attitude.pitch = 0.0f;
    attitude.yaw   = 0.0f;
}
