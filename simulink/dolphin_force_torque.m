function [Forces, Torques] = dolphin_force_torque(tail_freq, tail_amp, tail_yaw, ...
    pec_left, pec_right, Vb, euler, omega, t, ...
    env, body, tail, pec, dorsal, aero)
%DOLPHIN_FORCE_TORQUE 돌고래 헬륨 드론의 힘/토크 계산
%
%  입력:
%    tail_freq  - 꼬리 진동 주파수 [Hz]
%    tail_amp   - 꼬리 진동 진폭 [rad]
%    tail_yaw   - 꼬리 좌우 편향 [rad]
%    pec_left   - 좌측 가슴지느러미 각도 [rad]
%    pec_right  - 우측 가슴지느러미 각도 [rad]
%    Vb         - 기체 좌표계 속도 [u; v; w] [m/s]
%    euler      - 오일러각 [phi; theta; psi] [rad]
%    omega      - 각속도 [p; q; r] [rad/s]
%    t          - 현재 시간 [s]
%    env, body, tail, pec, dorsal, aero - 파라미터 구조체
%
%  출력:
%    Forces  - [Fx; Fy; Fz] 기체 좌표계 [N]
%    Torques - [L; M; N] 기체 좌표계 [N·m]

phi   = euler(1);  % Roll
theta = euler(2);  % Pitch
psi   = euler(3);  % Yaw

u = Vb(1);  % 전진 속도
v = Vb(2);  % 횡 속도
w = Vb(3);  % 수직 속도
V_mag = norm(Vb);

p = omega(1);  % Roll rate
q = omega(2);  % Pitch rate
r = omega(3);  % Yaw rate

%% ========== 1. 부력 (Buoyancy) ==========
% 부력은 지구 좌표계에서 상향 → 기체 좌표계로 변환
F_buoy_earth = [0; 0; -(env.rho_air - env.rho_He) * body.V_envelope * env.g];
% NED 좌표계: Z가 하향이므로 부력은 -Z 방향

% DCM (Body → Earth) 역 = Earth → Body
R = angle2dcm(psi, theta, phi, 'ZYX');  % Earth→Body DCM
F_buoy_body = R * F_buoy_earth;

% 부력 토크 (CB-CG 오프셋에 의한 복원 모멘트)
T_buoy = cross(body.r_CB_CG, F_buoy_body);

%% ========== 2. 중력 (Gravity) ==========
F_grav_earth = [0; 0; body.m_total * env.g];  % NED: +Z = 하향
F_grav_body = R * F_grav_earth;

%% ========== 3. 꼬리지느러미 추진력 (Tail Thrust) ==========
% 순간 꼬리 각도
theta_tail = tail_amp * sin(2 * pi * tail_freq * t);

% 평균 추진력 (시간 평균)
F_thrust_mag = env.rho_air * pi^2 * tail.S_fin * tail_amp^2 * tail_freq^2 * tail.C_T;

% Yaw 편향에 의한 추력 분배
F_tail = [F_thrust_mag * cos(tail_yaw); ...   % 전진 (커플링: cos로 감소)
          F_thrust_mag * sin(tail_yaw); ...   % 횡방향 (Yaw 힘)
          0];

% 꼬리 토크
T_tail = cross(tail.r_tail, F_tail);
% 추가 Yaw 토크 (직접)
T_tail(3) = T_tail(3) + F_thrust_mag * sin(tail_yaw) * abs(tail.r_tail(1));

%% ========== 4. 가슴지느러미 (Pectoral Fins) ==========
% 가슴지느러미 힘은 속도 의존 + 직접 편향력
% 저속에서도 약간의 힘을 발생시키기 위해 최소 속도 보장
V_eff = max(V_mag, 0.1);  % 최소 유효 속도

% 좌측 지느러미
F_pec_L_mag = 0.5 * env.rho_air * V_eff^2 * pec.S_fin * pec.C_L_alpha * pec_left;
% 우측 지느러미
F_pec_R_mag = 0.5 * env.rho_air * V_eff^2 * pec.S_fin * pec.C_L_alpha * pec_right;

% 수직 분력 (고도 제어)
Fz_pec = -(F_pec_L_mag + F_pec_R_mag) * 0.5;

F_pec = [0; 0; Fz_pec];

% Roll 토크: 좌우 차이
T_roll_pec = (F_pec_L_mag - F_pec_R_mag) * pec.r_pec(2);
% Pitch 토크: 공통 성분
T_pitch_pec = (F_pec_L_mag + F_pec_R_mag) * 0.5 * pec.r_pec(1);

T_pec = [T_roll_pec; T_pitch_pec; 0];

%% ========== 5. 등지느러미 수동 감쇠 (Dorsal Fin Passive) ==========
T_dorsal = [-dorsal.C_damp_roll * p; ...   % Roll 감쇠
             0; ...                         % Pitch에는 영향 없음
            -dorsal.C_damp_yaw * r];        % Yaw 감쇠

%% ========== 6. 공기 항력 (Air Drag) ==========
if V_mag > 0.001
    F_drag = -0.5 * env.rho_air * aero.Cd * aero.S_ref * V_mag * Vb;
else
    F_drag = [0; 0; 0];
end

% 회전 감쇠 (공기 저항에 의한)
T_rot_damp = -0.001 * omega;

%% ========== 합산 ==========
Forces  = F_buoy_body + F_grav_body + F_tail + F_pec + F_drag;
Torques = T_buoy + T_tail + T_pec + T_dorsal + T_rot_damp;

end
