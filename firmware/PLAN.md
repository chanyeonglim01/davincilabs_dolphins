# 돌고래 헬륨 드론 — STM32 펌웨어 개발 계획

## 하드웨어 사양

| 항목 | 부품 | 무게 | 비고 |
|------|------|------|------|
| MCU | STM32G431KB (NUCLEO 보드 → 추후 custom PCB) | ~5g | SBUS RXINV 지원 |
| 수신기 | FrSky XM+ (SBUS) | ~1.6g | TX16S 호환, D16 프로토콜 |
| 조종기 | RadioMaster TX16S | - | 4-in-1 모듈 |
| IMU | MPU6050 | ~1g | I2C, 6축 |
| 서보 | SG51R × 4 (2.5g급) | ~10g | 꼬리(상하), 꼬리(좌우), 가슴L, 가슴R |
| 배터리 | 1S LiPo 300mAh | ~8g | + Boost 5V (서보/수신기용) |
| 전원 | 1S→5V Boost 레귤레이터 | ~2g | Pololu 5V Step-Up 등 |
| 전선/커넥터 | 30AWG 실리콘선 | ~10g | |
| **합계** | | **~38g** | 200g 예산 대비 충분 |

## 전원 구조

```
1S LiPo (3.7V)
├── Boost 5V → 수신기 (XM+), 서보 4개
└── LDO 3.3V → STM32, MPU6050
```

## SBUS 연결

```
XM+ SBUS OUT → STM32 USART1 RX (RXINV 하드웨어 반전)
100000 baud, 8E2, inverted
```

## 채널 매핑 (TX16S)

```
CH1 = Roll      (AETR)
CH2 = Pitch
CH3 = Throttle  (0~100%)
CH4 = Yaw
CH5 = Mode      (Manual/Stabilized)
```

## 펌웨어 디렉터리 구조

```
firmware/
├── autogen/                ← Simulink 생성 코드
│   ├── controller.c        ← cascade PID (자세제어기)
│   ├── controller.h
│   └── controller_types.h
├── drivers/
│   ├── sbus_rx.c/.h        ← SBUS 파싱 (UART ISR/DMA)
│   ├── imu.c/.h            ← MPU6050 I2C 읽기
│   ├── servo_pwm.c/.h      ← PWM 출력 4ch (TIM)
│   └── power.c/.h          ← 배터리 전압 ADC
├── middleware/
│   ├── att_estimator.c/.h  ← 자세 추정 (Complementary Filter)
│   ├── rc_normalize.c/.h   ← SBUS→정규화(-1~+1), deadband, trim
│   ├── mixer.c/.h          ← pec_L=pitch+roll, pec_R=pitch-roll
│   ├── failsafe.c/.h       ← RC timeout, IMU timeout → neutral
│   └── param.h             ← 파라미터 (게인, 한계값)
├── app/
│   ├── control_task.c/.h   ← 100Hz 메인 제어 루프
│   └── main.c              ← 초기화 + 스케줄러
├── Makefile / CMakeLists.txt
└── README.md
```

## 메인 제어 루프 (100Hz)

```c
void control_task_run(void) {
    // 1. SBUS 최신 프레임 읽기
    sbus_snapshot_t rc = sbus_get_latest();

    // 2. RC 정규화 + deadband + trim
    rc_cmd_t cmd = rc_normalize(rc);

    // 3. RC Valid 판단
    bool rc_valid = sbus_is_valid() && !sbus_is_timeout(100ms);

    // 4. IMU 읽기
    imu_data_t imu = imu_read();

    // 5. 자세 추정 (Complementary Filter)
    attitude_t att = estimator_update(imu, dt);

    // 6. 모드 판단
    mode_t mode = (cmd.ch5 > 0.5f) ? MODE_STABILIZED : MODE_MANUAL;

    // 7. 제어기 (Simulink 생성 코드 또는 직접 PID)
    ctrl_output_t ctrl;
    if (!rc_valid) {
        ctrl = SAFE_NEUTRAL;  // 서보 중립
    } else if (mode == MODE_MANUAL) {
        ctrl = manual_mixer(cmd);
    } else {
        // Simulink 생성 제어기
        controller_step(att, cmd, &ctrl);
    }

    // 8. Mixer + Saturation
    servo_cmd_t servo = mixer_apply(ctrl);

    // 9. 서보 PWM 출력
    servo_pwm_set(servo);

    // 10. 텔레메트리 (10Hz)
    if (tick % 10 == 0) {
        telemetry_send(att, servo, mode);
    }
}
```

## 확정된 제어기 게인 (Simulink에서 검증 완료)

### Cascade PID 구조
```
Outer (angle P):
  Roll:  Kp = 1.4
  Pitch: Kp = 0.25
  Yaw:   Kp = 1.0

Inner (rate PID, 100Hz):
  Roll(p):  P=0.30, I=0.01, D=0.10
  Pitch(q): P=0.20, I=0.00, D=0.02
  Yaw(r):   P=0.20, I=0.02, D=0.03
```

### Mixer
```
pec_L    = pitch_cmd + roll_cmd
pec_R    = pitch_cmd - roll_cmd
tail_yaw = yaw_cmd
tail_freq = throttle × 3.0 Hz
tail_amp  = 0.52 rad (고정)
```

### Saturation
```
pec_L/R:   ±0.61 rad (±35deg)
tail_yaw:  ±0.52 rad (±30deg)
tail_freq: 0~3 Hz
```

## 개발 단계

### Step 1: 벤치 테스트 (NUCLEO 보드)
- [ ] SBUS 수신 + 파싱 확인 (XM+ → USART1)
- [ ] MPU6050 I2C 읽기 확인
- [ ] 서보 PWM 4ch 출력 확인
- [ ] 자세 추정 (Complementary Filter) 확인
- [ ] RC→서보 Manual 모드 동작 확인

### Step 2: 제어기 탑재
- [ ] Simulink에서 controller.c 코드 생성
- [ ] Stabilized 모드 동작 확인 (벤치에서 손으로 기울여 복원 확인)
- [ ] Failsafe (RC 끊김 → neutral) 확인

### Step 3: 비행 테스트
- [ ] 엔벨로프 제작 + 헬륨 충전
- [ ] 부력 트림 조절 (-1g 음성부력)
- [ ] Manual 비행 테스트
- [ ] Stabilized 비행 테스트
- [ ] PID 게인 실기체 튜닝

### Step 4: 위치 제어 준비
- [ ] UWB 태그 탑재 (DWM1001 또는 커스텀)
- [ ] GCS 연동 (WiFi 또는 텔레메트리)
- [ ] 위치 제어기 추가

## 참고 라이브러리

| 라이브러리 | 용도 | 링크 |
|-----------|------|------|
| STM32 HAL | MCU 드라이버 | STM32CubeMX |
| MPU6050 HAL | IMU I2C | 직접 구현 또는 오픈소스 |
| SBUS 파싱 | RC 수신 | 직접 구현 (UART ISR) |
| Madgwick/Complementary | 자세 추정 | 직접 구현 |
