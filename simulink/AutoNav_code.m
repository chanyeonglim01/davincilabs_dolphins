function [Ref_Att_Auto, TailFreq_Auto, PecCommon_Auto, TailPitch_Auto, wp_idx_out] = AutoNav(pos_uwb, euler, speed_mag, clock_t)
%#codegen
%% AutoNav: 위치 제어기 (LOS + 미리 꺾기)
%%
%% 핵심: 현재 WP에 가까워지면 다음 WP 방향을 미리 블렌딩
%%       → 코너에서 자연스럽게 턴 시작

%% ========== 파라미터 ==========
WP = [ 0,  0, -1.5;
       5,  0, -1.5;
       5,  5, -1.5;
       0,  5, -1.5;
       0,  0, -1.5];
N_wp = 5;

% WP 전환
R_switch = 1.0;          % WP 전환 반경 [m]
R_blend = 2.5;           % 다음 WP 방향 블렌딩 시작 거리 [m]

% LOS
T_look = 0.6;
L_look_min = 0.4;
L_look_max = 1.0;
K_ct = 1.5;
psi_rate_max = 55 * pi/180;  % 빠른 턴

% Speed
u_cruise = 1.0;
u_corner = 0.5;       % 코너 더 감속
Kp_u = 0.8;
Ki_u = 0.15;
freq_min = 0.5;
freq_max = 3.0;

% Altitude - tail pitch
Kp_h_tail = 0.15;
tail_pitch_max = 0.25;
rho_air = 1.225;
S_tail_area = 0.02;
C_T = 0.30;
tail_amp_nom = 0.52;
F_neg_buoy = 0.0005 * 9.81;

% Altitude - pec common
Kp_h_pec = 0.03;
pec_common_max = 0.10;
S_pec = 0.01;
CL_alpha = 2*pi;

% Bank
K_bank = 0.10;
phi_max = 3 * pi/180;

%% ========== Persistent ==========
persistent wp_idx u_integral prev_psi_ref prev_height
dt = 0.1;

if isempty(wp_idx) || clock_t < dt
    wp_idx = 1;
    u_integral = 0;
    prev_psi_ref = 0;
    prev_height = 1.5;
end

%% ========== 상태 ==========
x = pos_uwb(1);  y = pos_uwb(2);  z = pos_uwb(3);
psi = euler(3);
height = -z;
u_meas = max(speed_mag, 0.0);

%% ========== 1. Waypoint Manager ==========
% 현재 목표 WP
tgt_x = WP(wp_idx, 1);
tgt_y = WP(wp_idx, 2);
dist_to_wp = sqrt((x - tgt_x)^2 + (y - tgt_y)^2);

% WP 전환
if dist_to_wp < R_switch && wp_idx < N_wp
    wp_idx = wp_idx + 1;
end

% 현재/다음 WP
tgt_x = WP(wp_idx, 1);
tgt_y = WP(wp_idx, 2);
tgt_z = WP(wp_idx, 3);
h_ref = -tgt_z;
dist_to_wp = sqrt((x - tgt_x)^2 + (y - tgt_y)^2);

%% ========== 2. Guidance: LOS + 미리 꺾기 ==========
% 현재 WP로의 heading
psi_to_current = atan2(tgt_y - y, tgt_x - x);

% 다음 WP가 있으면 블렌딩
if wp_idx < N_wp && dist_to_wp < R_blend
    next_x = WP(wp_idx + 1, 1);
    next_y = WP(wp_idx + 1, 2);
    psi_to_next = atan2(next_y - y, next_x - x);

    % 블렌딩 비율: WP에 가까울수록 다음 WP 방향 비중 증가
    % dist = R_blend → alpha = 0 (현재 WP만)
    % dist = 0       → alpha = 0.7 (다음 WP 70%)
    alpha = 0.7 * (1.0 - dist_to_wp / R_blend);
    alpha = max(min(alpha, 0.7), 0.0);

    % 각도 블렌딩 (wrap-safe)
    dpsi = atan2(sin(psi_to_next - psi_to_current), cos(psi_to_next - psi_to_current));
    psi_desired = psi_to_current + alpha * dpsi;
    psi_desired = atan2(sin(psi_desired), cos(psi_desired));
else
    psi_desired = psi_to_current;
end

% psi_ref rate limiting
psi_err_raw = atan2(sin(psi_desired - prev_psi_ref), cos(psi_desired - prev_psi_ref));
dpsi_cmd = max(min(psi_err_raw, psi_rate_max * dt), -psi_rate_max * dt);
psi_ref = prev_psi_ref + dpsi_cmd;
psi_ref = atan2(sin(psi_ref), cos(psi_ref));
prev_psi_ref = psi_ref;

% heading error
psi_err = atan2(sin(psi_ref - psi), cos(psi_ref - psi));

% 속도: 코너 접근 시 감속
if dist_to_wp < R_blend && wp_idx < N_wp
    u_ref = u_corner + (u_cruise - u_corner) * (dist_to_wp / R_blend);
else
    u_ref = u_cruise;
end

%% ========== 3. Speed Controller (PI) ==========
u_err = u_ref - u_meas;
u_integral = u_integral + u_err * dt;
u_integral = max(min(u_integral, 3.0), -1.0);
tail_freq = Kp_u * u_err + Ki_u * u_integral;
tail_freq = max(min(tail_freq, freq_max), freq_min);
tail_freq = max(tail_freq, 1.1);  % altitude floor

%% ========== 4. Altitude ==========
h_err = h_ref - height;
prev_height = height;

% Tail pitch (primary)
F_thr_est = rho_air * pi^2 * S_tail_area * tail_amp_nom^2 * tail_freq^2 * C_T;
F_thr_est = max(F_thr_est, 0.001);
tail_pitch_ff = -asin(min(max(F_neg_buoy / F_thr_est, -0.4), 0.4));
tail_pitch_fb = -(Kp_h_tail * h_err);
tail_pitch_cmd = tail_pitch_ff + tail_pitch_fb;
tail_pitch_cmd = max(min(tail_pitch_cmd, tail_pitch_max), -tail_pitch_max);

% Pec common (secondary)
u_eff = max(u_meas, 0.65);
pec_ff = F_neg_buoy / (rho_air * u_eff^2 * S_pec * CL_alpha) * 0.5;
pec_fb = Kp_h_pec * h_err;
pec_common = pec_ff + pec_fb;
pec_common = max(min(pec_common, pec_common_max), -pec_common_max);

%% ========== 5. Bank Turn ==========
phi_bank = K_bank * psi_err;
phi_bank = max(min(phi_bank, phi_max), -phi_max);
if u_meas < 0.7
    phi_bank = 0;
end

%% ========== 출력 ==========
Ref_Att_Auto = [phi_bank; 0; psi_ref];
TailFreq_Auto = tail_freq;
PecCommon_Auto = pec_common;
TailPitch_Auto = tail_pitch_cmd;
wp_idx_out = wp_idx;

end
