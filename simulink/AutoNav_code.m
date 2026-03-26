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
       5,  0, -1.5;
       5,  5, -1.5;
       0,  5, -1.5;
       0,  0, -1.5];
N_wp = 5;
R_switch = 0.5;      % 코너 정밀도 향상

% Guidance (LOS)
psi_rate_max = 45 * pi/180;  % psi_ref 변화율 [rad/s] — 물고기라 빠르게 턴
T_look = 0.6;                % lookahead time [s] — 짧을수록 경로 밀착
L_look_min = 0.5;            % minimum lookahead [m]
L_look_max = 1.2;            % maximum lookahead [m]
K_ct = 1.5;                  % cross-track correction gain

% Speed
u_cruise = 1.0;       % 순항 약간 낮춤
u_corner = 0.6;       % 코너 더 감속
psi_slow_thresh = 15 * pi/180;  % 더 일찍 감속 시작
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

%% ========== 1. Waypoint Manager + LOS Segment ==========
% wp_idx is the active segment start index: WP_A = WP(wp_idx), WP_B = WP(wp_idx+1)
if wp_idx > N_wp - 1
    wp_idx = N_wp - 1;
end

WP_A = WP(wp_idx, :);
WP_B = WP(wp_idx + 1, :);

seg_x = WP_B(1) - WP_A(1);
seg_y = WP_B(2) - WP_A(2);
seg_len = sqrt(seg_x^2 + seg_y^2);
if seg_len < 1e-6
    seg_len = 1e-6;
end
t_hat_x = seg_x / seg_len;
t_hat_y = seg_y / seg_len;

rel_x = x - WP_A(1);
rel_y = y - WP_A(2);
s_along = rel_x * t_hat_x + rel_y * t_hat_y;
e_ct = -rel_x * t_hat_y + rel_y * t_hat_x;  % signed cross-track error
dist_to_B = sqrt((x - WP_B(1))^2 + (y - WP_B(2))^2);

% along-track progress 기반 waypoint 전환
if ((s_along >= seg_len - R_switch) || (dist_to_B < R_switch)) && (wp_idx < N_wp - 1)
    wp_idx = wp_idx + 1;
    if wp_idx > N_wp - 1
        wp_idx = N_wp - 1;
    end

    WP_A = WP(wp_idx, :);
    WP_B = WP(wp_idx + 1, :);

    seg_x = WP_B(1) - WP_A(1);
    seg_y = WP_B(2) - WP_A(2);
    seg_len = sqrt(seg_x^2 + seg_y^2);
    if seg_len < 1e-6
        seg_len = 1e-6;
    end
    t_hat_x = seg_x / seg_len;
    t_hat_y = seg_y / seg_len;

    rel_x = x - WP_A(1);
    rel_y = y - WP_A(2);
    s_along = rel_x * t_hat_x + rel_y * t_hat_y;
    e_ct = -rel_x * t_hat_y + rel_y * t_hat_x;
end

tgt_z = WP_B(3);
h_ref = -tgt_z;

%% ========== 2. Guidance (LOS line following + rate limit) ==========
look_dist = max(min(T_look * max(u_meas, 0.4), L_look_max), L_look_min);
s_proj = max(min(s_along, seg_len), 0.0);
look_s = min(s_proj + look_dist, seg_len);

% LOS lookahead point on active segment
look_x = WP_A(1) + look_s * t_hat_x;
look_y = WP_A(2) + look_s * t_hat_y;

% path heading + cross-track correction
psi_path = atan2(seg_y, seg_x);
psi_ct = atan2(-K_ct * e_ct, look_dist);
psi_desired = atan2(sin(psi_path + psi_ct), cos(psi_path + psi_ct));

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
wp_idx_out = min(wp_idx + 1, N_wp);

end
