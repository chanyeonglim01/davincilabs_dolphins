function [Ref_Att_Auto, TailFreq_Auto, PecCommon_Auto, TailPitch_Auto, wp_idx_out] = AutoNav(pos_uwb, euler, speed_mag, clock_t)
%#codegen
%% AutoNav: 위치 제어기 (Line/Arc fillet path following)
%%
%% 입력:
%%   pos_uwb(3x1): UWB 위치 [x,y,z] (NED, z-down)
%%   euler(3x1):   [phi, theta, psi]
%%   speed_mag(1x1): body speed [m/s]
%%   clock_t(1x1): 시뮬레이션 시간 [s]
%%
%% 출력:
%%   Ref_Att_Auto(3x1): [roll_ref, pitch_ref, psi_ref]
%%   TailFreq_Auto(1x1): 꼬리 주파수 [Hz]
%%   PecCommon_Auto(1x1): pec 공통 편향 [rad]
%%   TailPitch_Auto(1x1): 꼬리 상하 편향 [rad]
%%   wp_idx_out(1x1): 현재 WP 인덱스

%% ========== 파라미터 ==========
WP = [ 0,  0, -1.5;
       5,  0, -1.5;
       5,  5, -1.5;
       0,  5, -1.5;
       0,  0, -1.5];
N_wp = 5;

% Path fillet
R_fillet = 1.0;          % 코너 원호 반경 [m]
arc_entry_margin = 0.3;  % 직선 끝에서 원호 진입 여유 [m]
arc_exit_deg = 10;       % 원호 종료 조건 [deg]

% Guidance (LOS)
T_look = 0.6;
L_look_min = 0.4;
L_look_max = 1.0;
psi_rate_max = 45 * pi/180;

% Speed
u_cruise = 1.0;
u_corner = 0.6;
Kp_u = 0.8;
Ki_u = 0.15;
freq_min = 0.5;
freq_max = 3.0;

% Altitude — tail pitch (primary)
Kp_h_tail = 0.15;
tail_pitch_max = 0.25;
rho_air = 1.225;
S_tail_area = 0.02;
C_T = 0.30;
tail_amp_nom = 0.52;
F_neg_buoy = 0.0005 * 9.81;

% Altitude — pec common (secondary)
Kp_h_pec = 0.03;
pec_common_max = 0.10;
S_pec = 0.01;
CL_alpha = 2*pi;

% Bank turn
K_bank = 0.10;
phi_max = 3 * pi/180;

%% ========== Persistent ==========
persistent wp_idx u_integral prev_psi_ref prev_height path_mode
% path_mode: 0=LINE, 1=ARC
if isempty(wp_idx)
    wp_idx = 1;
    u_integral = 0;
    prev_psi_ref = 0;
    prev_height = 1.5;
    path_mode = 0;  % LINE
end

dt = 0.1;  % 10Hz

%% ========== 상태 ==========
x = pos_uwb(1);  y = pos_uwb(2);  z = pos_uwb(3);
psi = euler(3);
height = -z;
u_meas = speed_mag;

%% ========== 1. Segment 정의 ==========
seg_idx = max(min(wp_idx, N_wp-1), 1);
WP_A = WP(seg_idx, :);
WP_B = WP(min(seg_idx+1, N_wp), :);

seg_x = WP_B(1) - WP_A(1);
seg_y = WP_B(2) - WP_A(2);
seg_len = sqrt(seg_x^2 + seg_y^2);
if seg_len < 1e-6, seg_len = 1e-6; end
t_hat_x = seg_x / seg_len;
t_hat_y = seg_y / seg_len;

% along-track, cross-track
rel_x = x - WP_A(1);
rel_y = y - WP_A(2);
s_along = rel_x * t_hat_x + rel_y * t_hat_y;
e_ct = -rel_x * t_hat_y + rel_y * t_hat_x;

% 고도 목표
tgt_z = WP_B(3);
h_ref = -tgt_z;

%% ========== 2. Line/Arc 모드 전환 ==========
if path_mode == 0  % LINE 모드
    % 직선 끝에 가까우면 ARC로 전환
    if s_along >= seg_len - R_fillet - arc_entry_margin
        path_mode = 1;  % ARC로 전환
    end

    % WP 도달 (segment 끝)
    dist_to_B = sqrt((x - WP_B(1))^2 + (y - WP_B(2))^2);
    if dist_to_B < 0.5 && seg_idx < N_wp-1
        wp_idx = wp_idx + 1;
        path_mode = 0;
    end
else  % ARC 모드
    % 원호 종료: 다음 segment 방향에 가까워지면
    if seg_idx < N_wp-1
        WP_C = WP(min(seg_idx+2, N_wp), :);
        next_seg_x = WP_C(1) - WP_B(1);
        next_seg_y = WP_C(2) - WP_B(2);
        next_heading = atan2(next_seg_y, next_seg_x);
        heading_err = abs(atan2(sin(psi - next_heading), cos(psi - next_heading)));

        if heading_err < arc_exit_deg * pi/180
            wp_idx = wp_idx + 1;
            path_mode = 0;  % LINE으로 복귀
        end

        % timeout: WP_B 근처 또는 지나갔으면 강제 전환
        dist_to_B2 = sqrt((x - WP_B(1))^2 + (y - WP_B(2))^2);
        if dist_to_B2 < 1.0 || s_along > seg_len + 0.5
            wp_idx = wp_idx + 1;
            path_mode = 0;
        end
    else
        path_mode = 0;
    end
end

% wp_idx 범위 제한
wp_idx = max(min(wp_idx, N_wp-1), 1);

% 현재 segment 재계산 (wp_idx가 바뀌었을 수 있음)
seg_idx = wp_idx;
WP_A = WP(seg_idx, :);
WP_B = WP(min(seg_idx+1, N_wp), :);
seg_x = WP_B(1) - WP_A(1);
seg_y = WP_B(2) - WP_A(2);
seg_len = sqrt(seg_x^2 + seg_y^2);
if seg_len < 1e-6, seg_len = 1e-6; end
t_hat_x = seg_x / seg_len;
t_hat_y = seg_y / seg_len;
rel_x = x - WP_A(1);
rel_y = y - WP_A(2);
s_along = rel_x * t_hat_x + rel_y * t_hat_y;
e_ct = -rel_x * t_hat_y + rel_y * t_hat_x;

%% ========== 3. Guidance ==========
if path_mode == 0  % LINE: LOS 직선 추종
    look_dist = max(min(T_look * max(u_meas, 0.4), L_look_max), L_look_min);
    s_proj = max(min(s_along, seg_len), 0.0);
    look_s = min(s_proj + look_dist, seg_len);

    look_x = WP_A(1) + look_s * t_hat_x;
    look_y = WP_A(2) + look_s * t_hat_y;

    psi_path = atan2(seg_y, seg_x);
    K_ct = 1.5;
    psi_ct = atan2(-K_ct * e_ct, look_dist);
    psi_desired = atan2(sin(psi_path + psi_ct), cos(psi_path + psi_ct));

    u_ref = u_cruise;

else  % ARC: 코너 WP 방향으로 부드럽게 턴
    % 단순화: WP_B를 향해 heading, 속도 감속
    dx = WP_B(1) - x;
    dy = WP_B(2) - y;
    psi_desired = atan2(dy, dx);
    u_ref = u_corner;
end

% psi_ref rate limiting
psi_err_raw = atan2(sin(psi_desired - prev_psi_ref), cos(psi_desired - prev_psi_ref));
dpsi = max(min(psi_err_raw, psi_rate_max * dt), -psi_rate_max * dt);
psi_ref = prev_psi_ref + dpsi;
psi_ref = atan2(sin(psi_ref), cos(psi_ref));
prev_psi_ref = psi_ref;

% heading error
psi_err = atan2(sin(psi_ref - psi), cos(psi_ref - psi));

%% ========== 4. Speed Controller (PI) ==========
u_err = u_ref - u_meas;
u_integral = u_integral + u_err * dt;
u_integral = max(min(u_integral, 3.0), -1.0);
tail_freq = Kp_u * u_err + Ki_u * u_integral;
tail_freq = max(min(tail_freq, freq_max), freq_min);
tail_freq = max(tail_freq, 1.1);  % altitude hold floor

%% ========== 5. Altitude ==========
h_err = h_ref - height;
hdot = (height - prev_height) / dt;
prev_height = height;

% 5a. Tail pitch (primary)
F_thr_est = rho_air * pi^2 * S_tail_area * tail_amp_nom^2 * tail_freq^2 * C_T;
F_thr_est = max(F_thr_est, 0.001);
tail_pitch_ff = -asin(min(max(F_neg_buoy / F_thr_est, -0.4), 0.4));
tail_pitch_fb = -(Kp_h_tail * h_err);
tail_pitch_cmd = tail_pitch_ff + tail_pitch_fb;
tail_pitch_cmd = max(min(tail_pitch_cmd, tail_pitch_max), -tail_pitch_max);

% 5b. Pec common (secondary)
u_eff = max(u_meas, 0.65);
pec_ff = F_neg_buoy / (rho_air * u_eff^2 * S_pec * CL_alpha) * 0.5;
pec_fb = Kp_h_pec * h_err;
pec_common = pec_ff + pec_fb;
pec_common = max(min(pec_common, pec_common_max), -pec_common_max);

%% ========== 6. Bank Turn ==========
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
wp_idx_out = min(seg_idx + 1, N_wp);

end
