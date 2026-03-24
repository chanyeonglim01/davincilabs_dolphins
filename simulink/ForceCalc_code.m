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
V_env   = 0.35;     % 엔벨로프 체적 [m³]
m_total = 0.50;     % 총 질량 [kg]

% 꼬리
S_tail  = 0.02;     % 꼬리 면적 [m²]
C_T     = 0.30;     % 추력계수
r_tail_x = -0.80;   % 꼬리 x위치 [m] (후방)

% 가슴지느러미
S_pec    = 0.01;    % 면적 [m²]
CL_alpha = 2*pi;    % 양력 기울기 [1/rad]
r_pec_y  = 0.25;    % y위치 [m]
r_pec_x  = 0.10;    % x위치 [m]

% 등지느러미 (고정, 수동 감쇠)
C_damp_yaw  = 0.005;
C_damp_roll = 0.003;

% 공기 항력
Cd    = 0.04;
S_ref = 0.15;       % 기준 면적 [m²]

% 부력-무게중심 오프셋
r_CB_CG = [0; 0; 0.05];  % CB가 CG보다 5cm 위

%% ========== 서보 입력 분리 ==========
tail_freq    = servo_in(1);
tail_amp     = servo_in(2);
tail_yaw_cmd = servo_in(3);
pec_left     = servo_in(4);
pec_right    = servo_in(5);

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
V_eff = max(V_mag, 0.1);  % 최소 유효속도 (정지시에도 약간의 효과)

F_pL = 0.5 * rho_air * V_eff^2 * S_pec * CL_alpha * pec_left;
F_pR = 0.5 * rho_air * V_eff^2 * S_pec * CL_alpha * pec_right;

% 수직 분력 (고도 제어)
Fz_pec = -(F_pL + F_pR) * 0.5;

% Roll 토크 (좌우 차이)
T_roll_pec = (F_pL - F_pR) * r_pec_y;
% Pitch 토크 (공통 성분)
T_pitch_pec = (F_pL + F_pR) * 0.5 * r_pec_x;

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
