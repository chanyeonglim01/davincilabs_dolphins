function [Ref_Att_Auto, TailFreq_Auto, PecCommon_Auto, TailPitch_Auto, wp_idx_out] = AutoNav(pos_uwb, euler, speed_mag, clock_t)
%#codegen
%% AutoNav: 위치 제어기 (비홀로노믹 돌고래 드론)
%% 입력:
%%   pos_uwb(3x1): UWB 위치 [x,y,z] (NED, z-down)
%%   euler(3x1):   [phi, theta, psi]
%%   speed_mag(1x1): body speed [m/s] (from pos derivative)
%%   clock_t(1x1): 시뮬레이션 시간 [s]
%%
%% 출력:
%%   Ref_Att_Auto(3x1): [roll_ref, pitch_ref, psi_ref]
%%   TailFreq_Auto(1x1): 꼬리 주파수 [Hz]
%%   PecCommon_Auto(1x1): 가슴지느러미 공통 편향 [rad] (고도 보조)
%%   TailPitch_Auto(1x1): 꼬리 상하 편향 [rad] (고도 주제어)
%%   wp_idx_out(1x1):    현재 WP 인덱스

%% ========== 파라미터 ==========
WP = [ 0,  0, -1.5;
       3,  0, -1.5;
       3,  3, -1.5;
       0,  3, -1.5;
       0,  0, -1.5];
N_wp = 5;
R_switch = 0.8;      % 코너 통과 허용 반경 확대

% Guidance
psi_rate_max = 15 * pi/180;  % psi_ref 변화율 제한 [rad/s]

% Speed
u_cruise = 1.2;
u_corner = 0.9;
psi_slow_thresh = 25 * pi/180;
Kp_u = 0.8;
Ki_u = 0.15;
freq_min = 0.5;
freq_max = 3.0;

% Altitude — tail pitch (primary)
Kp_h_tail = 0.15;      % rad/m
Kd_h_tail = 0.0;       % rad/(m/s) (hdot 불안정하므로 일단 P-only)
tail_pitch_max = 0.25;  % rad
rho_air = 1.225;
S_tail_area = 0.02;
C_T = 0.30;
tail_amp_nom = 0.52;
F_neg_buoy = 0.0005 * 9.81;  % -0.5g

% Altitude — pec common (secondary trim)
Kp_h_pec = 0.03;       % rad/m
pec_common_max = 0.10;  % rad (보조 trim만)
S_pec = 0.01;
CL_alpha = 2*pi;

%% ========== Persistent ==========
persistent wp_idx u_integral prev_psi_ref prev_height
if isempty(wp_idx)
    wp_idx = 1;
    u_integral = 0;
    prev_psi_ref = 0;
    prev_height = 1.5;
end

dt = 0.1;  % 10Hz

%% ========== 상태 ==========
x = pos_uwb(1);  y = pos_uwb(2);  z = pos_uwb(3);
psi = euler(3);
height = -z;
u_meas = speed_mag;  % from position derivative

%% ========== 1. Waypoint Manager ==========
wp_x = WP(wp_idx,1);  wp_y = WP(wp_idx,2);
dist = sqrt((x-wp_x)^2 + (y-wp_y)^2);

% along-track 기반: 거리 < R_switch 또는 지나쳤을 때
if dist < R_switch && wp_idx < N_wp
    wp_idx = wp_idx + 1;
end

tgt_x = WP(wp_idx,1);  tgt_y = WP(wp_idx,2);  tgt_z = WP(wp_idx,3);
h_ref = -tgt_z;

%% ========== 2. Guidance (heading to WP + rate limit) ==========
dx = tgt_x - x;  dy = tgt_y - y;
psi_desired = atan2(dy, dx);

% psi_ref rate limiting
psi_err_raw = atan2(sin(psi_desired - prev_psi_ref), cos(psi_desired - prev_psi_ref));
dpsi = max(min(psi_err_raw, psi_rate_max * dt), -psi_rate_max * dt);
psi_ref = prev_psi_ref + dpsi;
psi_ref = atan2(sin(psi_ref), cos(psi_ref));  % wrap
prev_psi_ref = psi_ref;

% heading error for speed decision
psi_err = atan2(sin(psi_ref - psi), cos(psi_ref - psi));

%% ========== 3. Speed Controller (PI with feedback) ==========
if abs(psi_err) > psi_slow_thresh
    u_ref = u_corner;
else
    u_ref = u_cruise;
end

u_err = u_ref - u_meas;
u_integral = u_integral + u_err * dt;
u_integral = max(min(u_integral, 3.0), -1.0);  % anti-windup

tail_freq = Kp_u * u_err + Ki_u * u_integral;
tail_freq = max(min(tail_freq, freq_max), freq_min);
% altitude hold floor: 고도 유지 위해 최소 추력 보장
tail_freq = max(tail_freq, 1.1);

%% ========== 4. Altitude ==========
h_err = h_ref - height;
hdot = (height - prev_height) / dt;
prev_height = height;

% 4a. Tail pitch (primary) — feedforward + PD
F_thr_est = rho_air * pi^2 * S_tail_area * tail_amp_nom^2 * tail_freq^2 * C_T;
F_thr_est = max(F_thr_est, 0.001);
tail_pitch_ff = -asin(min(max(F_neg_buoy / F_thr_est, -0.4), 0.4));  % 음수=위(NED)
tail_pitch_fb = -(Kp_h_tail * h_err - Kd_h_tail * hdot);           % 고도 부족→위
tail_pitch_cmd = tail_pitch_ff + tail_pitch_fb;
tail_pitch_cmd = max(min(tail_pitch_cmd, tail_pitch_max), -tail_pitch_max);

% 4b. Pec common (secondary trim)
u_eff = max(u_meas, 0.65);
pec_ff = F_neg_buoy / (rho_air * u_eff^2 * S_pec * CL_alpha) * 0.5;  % 50% only
pec_fb = Kp_h_pec * h_err;
pec_common = pec_ff + pec_fb;
pec_common = max(min(pec_common, pec_common_max), -pec_common_max);

%% ========== 출력 ==========
Ref_Att_Auto = [0; 0; psi_ref];
TailFreq_Auto = tail_freq;
PecCommon_Auto = pec_common;
TailPitch_Auto = tail_pitch_cmd;
wp_idx_out = wp_idx;

end
