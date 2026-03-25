# 돌고래 헬륨 드론 — 전체 개발 계획

## 프로젝트 개요
- 2m × 0.50m 돌고래 형상 헬륨 드론
- 실내 군집 아트 퍼포먼스 (5~10대)
- 음성부력 -1g, 꼬리 추진, 가슴지느러미 자세제어

---

## 1. Simulink 모델 (설계/검증/코드생성)

### 1.1 플랜트 모델 ✅ 완료
- 6DoF (Euler Angles) + MATLAB Function (ForceCalc)
- 부력, 중력, 꼬리 추진, 가슴지느러미, 등지느러미 감쇠, 항력
- 파라미터: 0.50m 직경, 0.262m³, 279g, Cd=0.30
- Codex 검증 완료

### 1.2 자세 제어기 ✅ 완료
- Cascade PID (Outer angle P + Inner rate PID)
- Simulink 기본 블록만 사용 (MATLAB Function 없음)
- 확정 게인:

| 축 | Outer P | Inner P | Inner I | Inner D |
|----|---------|---------|---------|---------|
| Roll(p) | 1.4 | 0.30 | 0.01 | 0.10 |
| Pitch(q) | 0.25 | 0.20 | 0.00 | 0.02 |
| Yaw(r) | 1.0 | 0.20 | 0.02 | 0.03 |

### 1.3 RC 모드 ✅ 완료
- RC_Input: SBUS 채널 시뮬레이션 (Constant/Step)
- ManualMixer: RC→서보 직접
- Mode Switch: CH5 (Manual/Stabilized)
- Deadband ±0.05, RC_Valid failsafe
- Servo dynamics: Rate Limiter + 1차 지연

### 1.4 제어기 C 코드 생성 ⬜ 미완료
- [ ] Simulink Embedded Coder로 AttitudeController → controller.c 생성
- [ ] 입력: attitude(3), angular_rate(3), rc_cmd(4), mode(1)
- [ ] 출력: tail_freq, tail_yaw, pec_L, pec_R
- [ ] Reusable function 패키징 (controller_init/reset/step만)
- [ ] 생성된 코드 firmware/autogen/에 배치
- [ ] HAL/드라이버 의존성 없이 순수 제어 알고리즘만 생성
- [ ] SIL(Software-In-the-Loop) 검증 후 배포

### 1.5 시동 시퀀스 ⬜ 미완료 (위치제어보다 먼저!)
- [ ] Launch: tail ramp-up (0→2Hz, 4초), pectoral neutral
- [ ] Transition: u > 0.6m/s에서 roll/pitch PID on (gain scheduling)
- [ ] Cruise: u > 0.9m/s에서 full cascade PID + I항 활성화
- [ ] Low-speed fallback: u < 0.5m/s → PID off, neutral
- [ ] Switch 블록 기반 (Stateflow 불필요)

### 1.6 위치 제어기 ⬜ 미완료
- [ ] UWB 위치 피드백 모델링 (Simulink)
- [ ] 외부 루프: 위치 PID (heading + forward speed 구조)
- [ ] 비홀로노믹 시스템: 극좌표 기반 (거리 + 방위각)
- [ ] 고도 제어: 가슴지느러미 공통 틸트 (순항속도 확보 시만)
- [ ] Waypoint 추종 시뮬레이션
- [ ] 군집 다중 기체 시뮬레이션 (Model Reference)

---

## 2. STM32 펌웨어 (실기체)

### 2.1 하드웨어 사양

| 항목 | 부품 | 무게 | 비고 |
|------|------|------|------|
| MCU | STM32G431KB (NUCLEO → custom PCB) | ~5g | SBUS RXINV 지원 |
| 수신기 | FrSky XM+ (SBUS) | ~1.6g | TX16S D16 호환 |
| 조종기 | RadioMaster TX16S | - | 4-in-1 |
| IMU | ICM-20948 (9축, 자기장 포함) | ~1g | Yaw 절대방위용 mag |
| 서보 | 2.5g급 × 4 | ~10g | 꼬리(상하/좌우), 가슴L/R |
| 배터리 | 1S LiPo 300mAh | ~8g | |
| Boost 5V | Pololu 5V Step-Up (2A+) | ~2g | 서보 피크 전류 대비 |
| WiFi 모듈 | ESP32-C3 Mini 또는 별도 | ~2g | GCS 통신용 (Phase 6) |
| PCB/커넥터 | carrier PCB | ~3g | |
| 전선 (30AWG) | 하니스 | ~10g | |
| 링크/로드/혼 | 서보 연결 | ~5g | |
| UWB 태그 | DWM1001 커스텀 | ~5g | (Phase 6에서 추가) |
| **전자부 합계** | | **~55g** | Phase 3 기준 (UWB/WiFi 제외 ~48g) |

※ 200g 가용 예산 대비 충분 (엔벨로프 ~70g + 전자부 ~51g + 밸러스트 ~10g = ~131g)

### 2.2 전원 구조
```
1S LiPo (3.7V, 300mAh)
├── Boost 5V (peak 2A+) → XM+, 서보 4개
└── LDO 3.3V → STM32, ICM-20948
```

### 2.3 Yaw 절대방위
- ICM-20948 내장 자기장 센서로 heading 추정
- 또는 UWB dual-tag로 heading 계산 (Phase 6)
- IMU Yaw 드리프트를 mag/UWB로 보정

### 2.4 디렉터리 구조
```
firmware/
├── autogen/                ← Simulink 생성 (controller_init/step/reset만)
│   ├── controller.c/.h
│   └── controller_types.h
├── drivers/                ← HAL 의존, handwritten
│   ├── sbus_rx.c/.h        ← SBUS 파싱 (USART1, RXINV, DMA)
│   ├── imu.c/.h            ← ICM-20948 I2C/SPI
│   ├── servo_pwm.c/.h      ← PWM 4ch (TIM)
│   └── power.c/.h          ← 배터리 ADC + BEC 상태
├── middleware/              ← HAL 비의존, handwritten
│   ├── att_estimator.c/.h  ← Complementary/Madgwick + mag fusion
│   ├── rc_normalize.c/.h   ← SBUS→정규화(-1~+1), deadband, trim
│   ├── mixer.c/.h          ← pec_L=pitch+roll, pec_R=pitch-roll
│   ├── failsafe.c/.h       ← RC/IMU timeout → neutral + PID reset
│   └── param.h             ← 게인, 한계값, 트림
├── app/
│   ├── control_task.c/.h   ← 100Hz 메인 제어 루프
│   └── main.c              ← 초기화 + 스케줄러
├── CMakeLists.txt
└── PLAN.md
```

### 2.5 메인 루프 (100Hz)
```
1. SBUS 최신 프레임 읽기 (DMA ISR에서 수신)
2. RC 정규화 + deadband + trim
3. RC Valid 판단 (100ms timeout)
4. IMU 읽기 (가속도 + 자이로 + 자기장)
5. 자세 추정 (Madgwick + mag fusion)
6. 모드 판단 (CH5: Manual/Stabilized)
7. 제어기:
   - RC invalid → SAFE_NEUTRAL (서보 중립, PID reset)
   - Manual → manual_mixer(cmd)
   - Stabilized → controller_step(att, cmd) (Simulink 생성)
8. Mixer + Saturation
9. 서보 PWM 출력
10. 텔레메트리 (10Hz, UART/WiFi)
```

### 2.6 SIL/HIL 검증
- [ ] SIL: Simulink 생성 코드를 PC에서 플랜트 모델과 연동 검증
- [ ] HIL: STM32에 코드 올리고 Simulink 플랜트와 실시간 연동
- [ ] Log replay: 비행 로그를 Simulink에서 재생하여 제어기 검증

### 2.7 개발 단계
- [ ] Step 1: NUCLEO 벤치 — SBUS, IMU, 서보 개별 확인
- [ ] Step 2: 자세 추정 확인 — IMU 읽기 + Madgwick 출력 검증
- [ ] Step 3: 제어기 탑재 — Stabilized 벤치 테스트 (손으로 기울여 복원)
- [ ] Step 4: Failsafe 검증 — RC 끊김 → neutral, 모드 전환 → PID reset
- [ ] Step 5: 비행 테스트 — Manual → Stabilized
- [ ] Step 6: PID 실기체 튜닝

---

## 3. GCS (Ground Control Station)

### 3.1 아키텍처 — 중앙 집중형
```
UWB 앵커 (6~8개, 벽/천장 높이 분산)
    ↓ RTLS
GCS PC
├── UWB 위치 수신 (모든 드론 위치 취합)
├── 다중 드론 위치 제어기 (각 드론별 독립 PID)
├── 충돌 회피 (ORCA, ellipse footprint)
├── 안무 재생 엔진
└── WiFi/UDP → 각 드론에 명령 전송 (10~20Hz)
         ↓
    각 드론 (STM32 + WiFi 모듈)
    ├── 목표 위치(x,y,z) + 목표 Yaw 수신
    ├── 주변 드론 위치 수신 (onboard 충돌 회피용)
    └── 온보드 자세제어 (100Hz)
```

### 3.2 위치 추적 — UWB
- 앵커: 6~8개 (3D 정밀도를 위해 높이 분산 배치)
- 태그: DWM1001 커스텀 3~5g (상용 Pozyx 태그는 23g으로 과중)
- RTLS 업데이트율: 10대 × 10Hz = 100Hz aggregate (Pozyx Creator급은 60Hz까지)
- Z축 정밀도: 앵커 높이 배치에 민감 → 최소 2개 높이 레벨
- Yaw: UWB만으로 부족 → IMU mag fusion 또는 dual-tag heading

### 3.3 통신 프로토콜
```
GCS → 드론 (10~20Hz, UDP):
  - 목표 위치(x,y,z): 12 bytes
  - 목표 Yaw: 4 bytes
  - 주변 드론 위치 (N-1대): (N-1) × 12 bytes
  - 명령 시퀀스 번호: 2 bytes
  - command TTL: 200ms (초과 시 hold → failsafe)

드론 → GCS (10Hz, UDP):
  - 현재 위치(x,y,z): 12 bytes
  - 자세(roll,pitch,yaw): 12 bytes
  - 모드/상태/배터리: 4 bytes
```

### 3.4 Failsafe
- WiFi 끊김 → command TTL 초과 → 현재 위치 hold (200ms) → neutral + 착륙 (2s)
- UWB 끊김 → 위치 추정 freeze → 자세 hold만 유지 → 천천히 착륙

---

## 4. 군집 제어

### 4.1 위치 공유
- **중앙 집중형**: GCS가 모든 드론 위치를 취합하여 각 드론에 전송
- 각 드론은 자기 목표 + 주변 드론 위치를 수신
- 드론끼리 직접 통신 없음 (5~10대 규모에서 충분)

### 4.2 안무 시스템
- [ ] Keyframe 기반 (drone_id, t, x, y, z, led_color)
- [ ] 궤적 보간: Minimum Snap 또는 jerk-limited spline
- [ ] Blender 애니메이션 → 궤적 데이터 변환
- [ ] 음악 싱크 (비트 감지 → 키프레임)

### 4.3 충돌 회피
- [ ] ORCA (Optimal Reciprocal Collision Avoidance)
- [ ] 기체 형상: oriented capsule/ellipse (2.0m × 0.5m)
- [ ] 최소 분리거리: 기체 장축 기준 1.5m+ (보수적)
- [ ] 사전 충돌 검사 (offline) + 실시간 회피 (online)

### 4.4 포메이션
- [ ] V자 편대, 원형, 파동 패턴
- [ ] Virtual Structure 방식 (가상 강체 이동/회전)

---

## 5. 개발 순서 (Codex 검증 확정)

```
Phase 1  ✅ Simulink 플랜트 + 자세제어기 + RC 모드
Phase 2  ⬜ STM32 펌웨어 드라이버 (SBUS, IMU, 서보) + Manual 비행
Phase 3  ⬜ 엔벨로프 제작 + Manual RC 비행 테스트
Phase 4  ⬜ Simulink 시동 시퀀스 (Launch/Transition/Cruise)
Phase 5  ⬜ Simulink 위치 제어기 + 코드 생성 (전체 확정 후 한번에)
Phase 6  ⬜ Stabilized 비행 + 실기체 PID 튜닝 + SIL/HIL
Phase 7  ⬜ UWB + GCS 구축
Phase 8  ⬜ 군집 제어 + 안무 + 위치 공유
```
