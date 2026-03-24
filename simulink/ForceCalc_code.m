function [Forces, Torques] = ForceCalc(servo_in, Vb, euler_angles, omega_b, t)
%#codegen
%% 돌고래 헬륨 드론 힘/토크 계산
%% MATLAB Function 블록에 이 코드를 복사-붙여넣기 하세요
%%
%% 입력:
%%   servo_in(5x1): [tail_freq, tail_amp, tail_yaw, pec_left, pec_right]
%%   Vb(3x1):       기체 좌표계 속도 [u, v, w]
%%   euler_angles(3x1): [phi, theta, psi]
%%   omega_b(3x1):  각속도 [p, q, r]
%%   t(1x1):        시간 [s]
%%
%% 출력:
%%   Forces(3x1):  기체 좌표계 합력 [Fx, Fy, Fz]
%%   Torques(3x1): 기체 좌표계 합토크 [L, M, N]

Forces = zeros(3,1);
Torques = zeros(3,1);

%% ========== 파라미터 ==========
rho_air = 1.225;    % 공기 밀도 [kg/m³]
rho_He  = 0.164;    % 헬륨 밀도 [kg/m³]
g       = 9.81;     % 중력 가속도 [m/s²]

% 기체 형상 / 정적 trim
body_length   = 2.0;    % [m]
body_max_diam = 0.50;   % [m] (재설계: 0.58→0.50)
a_semi = body_length / 2;
b_semi = body_max_diam / 2;
V_env  = (4/3) * pi * a_semi * b_semi^2;

m_neutral   = (rho_air - rho_He) * V_env;
buoy_margin = -0.001;   % [kg], 약 -1 g 음성부력 (약간 무거움)
m_total     = m_neutral - buoy_margin;

% 꼬리
S_tail  = 0.02;     % 꼬리 면적 [m²]
C_T     = 0.30;     % 추력계수
r_tail_x = -0.80;   % 꼬리 x위치 [m] (후방)
tail_freq_min = 0.5;
tail_freq_max = 3.0;
tail_amp_max  = 0.70;
tail_yaw_max  = 0.52;

% 가슴지느러미
S_pec    = 0.01;    % 면적 [m²]
CL_alpha = 2*pi;    % 양력 기울기 [1/rad]
r_pec_y  = 0.25;    % y위치 [m]
r_pec_x  = 0.10;    % x위치 [m]
pec_delta_max   = 35*pi/180;
pec_alpha_stall = 15*pi/180;
pec_CL_max      = 1.20;
pec_V_min       = 0.05; % 저속 surrogate용 최소 유속 [m/s]

% 등지느러미 (고정, 수동 감쇠)
C_damp_yaw  = 0.005;
C_damp_roll = 0.003;

% 공기 항력
Cd    = 0.30;
S_ref = pi * b_semi^2;   % 정면 단면적 [m²]

% 부력-무게중심 오프셋
r_CB_CG = [0; 0; -0.05]; % CB가 CG보다 5cm 위 (NED z-down)

%% ========== 서보 입력 분리 ==========
tail_freq    = min(max(servo_in(1), tail_freq_min), tail_freq_max);
tail_amp     = min(max(servo_in(2), 0.0), tail_amp_max);
tail_yaw_cmd = min(max(servo_in(3), -tail_yaw_max), tail_yaw_max);
pec_left     = min(max(servo_in(4), -pec_delta_max), pec_delta_max);
pec_right    = min(max(servo_in(5), -pec_delta_max), pec_delta_max);

%% ========== 상태 변수 ==========
phi   = euler_angles(1);
theta = euler_angles(2);
psi   = euler_angles(3);

u = Vb(1); v = Vb(2); w = Vb(3);
V_mag = sqrt(u^2 + v^2 + w^2);

p = omega_b(1); q = omega_b(2); r = omega_b(3);

%% ========== 1. DCM (Earth → Body) ==========
cphi = cos(phi);  sphi = sin(phi);
cth  = cos(theta); sth = sin(theta);
cpsi = cos(psi);  spsi = sin(psi);

R = [ cth*cpsi,                 cth*spsi,                -sth;
      sphi*sth*cpsi-cphi*spsi,  sphi*sth*spsi+cphi*cpsi,  sphi*cth;
      cphi*sth*cpsi+sphi*spsi,  cphi*sth*spsi-sphi*cpsi,  cphi*cth];

%% ========== 2. 부력 (NED: Z 하향, 부력은 -Z) ==========
F_buoy_e = [0; 0; -(rho_air - rho_He) * V_env * g];
F_buoy_b = R * F_buoy_e;
T_buoy   = cross(r_CB_CG, F_buoy_b);

%% ========== 3. 중력 (NED: +Z 하향) ==========
F_grav_e = [0; 0; m_total * g];
F_grav_b = R * F_grav_e;

%% ========== 4. 꼬리 추진력 ==========
F_thr = rho_air * pi^2 * S_tail * tail_amp^2 * tail_freq^2 * C_T;

F_tail = [F_thr * cos(tail_yaw_cmd);    % 전진 (Yaw시 cos로 감소)
          F_thr * sin(tail_yaw_cmd);    % 횡방향
          0];

% Yaw 토크 (꼬리 좌우 편향)
T_tail = [0; 0; F_thr * sin(tail_yaw_cmd) * abs(r_tail_x)];

%% ========== 5. 가슴지느러미 ==========
% 정지 호버에서 양력이 생기지 않도록 전방 유속 기반으로 계산하되,
% 수치적으로 완전히 0이 되지 않게 작은 surrogate 유속을 둡니다.
V_pec = max(abs(u), pec_V_min);
q_pec = 0.5 * rho_air * V_pec^2;

alpha_pL = min(max(pec_left,  -pec_alpha_stall), pec_alpha_stall);
alpha_pR = min(max(pec_right, -pec_alpha_stall), pec_alpha_stall);
CL_pL = min(max(CL_alpha * alpha_pL, -pec_CL_max), pec_CL_max);
CL_pR = min(max(CL_alpha * alpha_pR, -pec_CL_max), pec_CL_max);

Fz_pec_L = -q_pec * S_pec * CL_pL; % body z-down, 음수는 upward
Fz_pec_R = -q_pec * S_pec * CL_pR;
Fz_pec = Fz_pec_L + Fz_pec_R;

% 좌: y=-r_pec_y, 우: y=+r_pec_y 로 가정한 모멘트
T_roll_pec  = r_pec_y * (Fz_pec_R - Fz_pec_L);
T_pitch_pec = -r_pec_x * Fz_pec;

%% ========== 6. 등지느러미 수동 감쇠 ==========
T_dorsal = [-C_damp_roll * p;    % Roll 감쇠
             0;                   % Pitch 무관
            -C_damp_yaw * r];     % Yaw 감쇠

%% ========== 7. 공기 항력 ==========
if V_mag > 0.001
    F_drag = -0.5 * rho_air * Cd * S_ref * V_mag * Vb;
else
    F_drag = zeros(3,1);
end

% 회전 감쇠
T_rot_damp = -0.001 * omega_b;

%% ========== 합산 ==========
Forces  = F_buoy_b + F_grav_b + F_tail + [0; 0; Fz_pec] + F_drag;
Torques = T_buoy + T_tail + [T_roll_pec; T_pitch_pec; 0] + T_dorsal + T_rot_damp;

end
