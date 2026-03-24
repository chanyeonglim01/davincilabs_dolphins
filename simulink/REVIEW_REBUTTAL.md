# 플랜트 모델 검증 반박 및 가이드 요청

## 동의 사항 (수정 예정)
1. **부력-중력 평형**: m_total=0.50kg이 과대. V_envelope=0.35m³ 유지 시 m_total≈0.37kg으로 조정
2. **r_CB_CG 부호**: NED에서 위는 -Z이므로 [0;0;-0.05]로 수정
3. **Yaw 토크 불일치**: dolphin_force_torque.m과 ForceCalc_code.m 간 Yaw 모멘트 계산 다름 → ForceCalc_code.m 기준 통일
4. **타원체 체적**: 2m×0.5m prolate spheroid=0.262m³인데 0.35m³로 설정됨. 직경 0.58m로 수정 또는 체적 0.262m³로 하향
5. **CL_alpha 45도 선형**: stall 각도 반영 saturation 추가
6. **종단속도 9.3m/s**: Cd 또는 S_ref 재보정 필요

## 부분 동의
- **V_eff=max(V_mag,0.1)**: 완전 제거 시 정지 상태 고도제어 불가. 값을 0.01로 줄이거나 대안 필요
- **꼬리 추력 차원**: A가 rad인데 길이스케일 없는건 맞지만 C_T에 흡수시킨 근사모델

## 반박
- **등지느러미 rate damper**: 의도적 설계. 저속 헬륨드론에서 full 공력모델은 불필요. 제어기 설계용 surrogate로 적절

## 가이드 요청
1. 일관된 파라미터 세트 (체적, 질량, 직경) 제안
2. 수정된 ForceCalc 수식
3. PID 자세제어기 설계를 위한 다음 단계
