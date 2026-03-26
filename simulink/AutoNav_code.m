function [Ref_Att_Auto, TailFreq_Auto, PecCommon_Auto, wp_idx_out] = AutoNav(pos_uwb, euler, speed_mag, clock_t)
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
%%   PecCommon_Auto(1x1): 가슴지느러미 공통 편향 [rad] (고도 제어)
%%   wp_idx_out(1x1):    현재 WP 인덱스

%% ========== 파라미터 ==========
WP = [ 0,  0, -1.5;
       3,  0, -1.5;
       3,  3, -1.5;
       0,  3, -1.5;
       0,  0, -1.5];
N_wp = 5;
R_switch = 0.5;

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

% Altitude (pec common direct)
Kp_h = 0.05;           % rad/m
pec_common_max = 0.15;  % rad
rho_air = 1.225;
S_pec = 0.01;
CL_alpha = 2*pi;
F_neg_buoy = 0.0005 * 9.81;  % 음성부력 0.0005 kg (-0.5g)

%% ========== Persistent ==========
persistent wp_idx u_integral prev_psi_ref
if isempty(wp_idx)
    wp_idx = 1;
    u_integral = 0;
    prev_psi_ref = 0;
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

%% ========== 4. Altitude (pec common direct) ==========
h_err = h_ref - height;
u_eff = max(u_meas, 0.65);  % 저속 floor / alt enable threshold

% feedforward: 음성부력 상쇄
pec_ff = F_neg_buoy / (rho_air * u_eff^2 * S_pec * CL_alpha);

% feedback
pec_fb = Kp_h * h_err;

pec_common = pec_ff + pec_fb;
pec_common = max(min(pec_common, pec_common_max), -pec_common_max);

%% ========== 출력 ==========
Ref_Att_Auto = [0; 0; psi_ref];  % pitch_ref = 0 (고도는 pec_common으로)
TailFreq_Auto = tail_freq;
PecCommon_Auto = pec_common;
wp_idx_out = wp_idx;

end
