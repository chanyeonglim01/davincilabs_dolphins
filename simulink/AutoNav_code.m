function [Ref_Att_Auto, TailFreq_Auto, PecCommon_Auto, TailPitch_Auto, wp_idx_out] = AutoNav(pos_uwb, euler, speed_mag, clock_t)
%#codegen
%% AutoNav: 위치 제어기 (Line/Arc fillet path following)
%
% 입력:
%   pos_uwb(3x1): UWB 위치 [x,y,z] (NED, z-down)
%   euler(3x1):   [phi, theta, psi]
%   speed_mag(1x1): 현재 속도 크기 [m/s]
%   clock_t(1x1): 시뮬레이션 시간 [s]
%
% 출력:
%   Ref_Att_Auto(3x1): [roll_ref, pitch_ref, psi_ref]
%   TailFreq_Auto(1x1): 꼬리 주파수 [Hz]
%   PecCommon_Auto(1x1): pec 공통 편향 [rad]
%   TailPitch_Auto(1x1): 꼬리 상하 편향 [rad]
%   wp_idx_out(1x1): 현재 active target waypoint index

%% ========== 파라미터 ==========
WP = [ 0,  0, -1.5;
       5,  0, -1.5;
       5,  5, -1.5;
       0,  5, -1.5;
       0,  0, -1.5];
N_wp = 5;

% Path fillet
R_fillet = 1.0;          % 코너 원호 반경 [m]
arc_entry_margin = 0.35; % Tin 직전 ARC 진입 여유 [m]
arc_slow_margin = 1.60;  % Tin 이전 감속 시작 거리 [m]
arc_exit_lat_tol = 0.80; % Tout 통과 판정용 lateral corridor [m]
final_wp_radius = 0.50;  % 마지막 WP 도달 반경 [m]

% Guidance (LOS)
T_look = 0.6;
L_look_min = 0.4;
L_look_max = 1.0;
psi_rate_max = 45 * pi/180;
K_ct = 1.5;
K_arc_radial = 2.0;      % 원호 반경 오차 보정 gain

% Speed
u_cruise = 1.0;
u_corner = 0.6;
Kp_u = 0.8;
Ki_u = 0.15;
freq_min = 0.5;
freq_max = 3.0;

% Altitude - tail pitch (primary)
Kp_h_tail = 0.15;
tail_pitch_max = 0.25;
rho_air = 1.225;
S_tail_area = 0.02;
C_T = 0.30;
tail_amp_nom = 0.52;
F_neg_buoy = 0.0005 * 9.81;

% Altitude - pec common (secondary)
Kp_h_pec = 0.03;
pec_common_max = 0.10;
S_pec = 0.01;
CL_alpha = 2*pi;

% Bank turn
K_bank = 0.10;
phi_max = 3 * pi/180;

%% ========== Persistent ==========
persistent wp_idx u_integral prev_psi_ref prev_height path_mode
% path_mode: 0 = LINE, 1 = ARC
dt = 0.1;  % 10 Hz

if isempty(wp_idx) || clock_t < dt
    wp_idx = 1;         % active incoming segment start index
    u_integral = 0;
    prev_psi_ref = 0;
    prev_height = 1.5;
    path_mode = 0;
end

%% ========== 상태 ==========
x = pos_uwb(1);
y = pos_uwb(2);
z = pos_uwb(3);
psi = euler(3);

height = -z;
u_meas = max(speed_mag, 0.0);
p_xy = [x; y];

%% ========== 1. 현재 primitive 계산 ==========
seg_idx = max(min(wp_idx, N_wp - 1), 1);
A = WP(seg_idx,     1:2).';
B = WP(seg_idx + 1, 1:2).';

v1 = B - A;
L1 = sqrt(v1(1)^2 + v1(2)^2);
if L1 < 1e-6
    L1 = 1e-6;
end
t1 = v1 / L1;

% 기본값: fillet 없음
arc_valid = false;
R_use = R_fillet;
d_use = 0.0;
Tin = B;
Tout = B;
C_arc = B;
alpha_in = 0.0;
alpha_out = 0.0;
turn_dir = 0.0;
line_end = B;

if seg_idx < N_wp - 1
    Cpt = WP(seg_idx + 2, 1:2).';
    v2 = Cpt - B;
    L2 = sqrt(v2(1)^2 + v2(2)^2);
    if L2 < 1e-6
        L2 = 1e-6;
    end
    t2 = v2 / L2;

    dot12 = t1(1) * t2(1) + t1(2) * t2(2);
    dot12 = min(max(dot12, -1.0), 1.0);
    delta = acos(dot12);
    turn_z = t1(1) * t2(2) - t1(2) * t2(1);

    if abs(turn_z) > 1e-3 && delta > 5 * pi/180 && delta < 175 * pi/180
        d_nom = R_fillet * tan(delta / 2);
        d_use = min(d_nom, 0.45 * L1);
        d_use = min(d_use, 0.45 * L2);

        if d_use > 0.05
            R_use = d_use / tan(delta / 2);
            if turn_z >= 0
                turn_dir = 1.0; % CCW
            else
                turn_dir = -1.0; % CW
            end

            Tin = B - d_use * t1;
            Tout = B + d_use * t2;

            n1_left = [-t1(2); t1(1)];
            C_arc = Tin + turn_dir * R_use * n1_left;

            alpha_in = atan2(Tin(2)  - C_arc(2), Tin(1)  - C_arc(1));
            alpha_out = atan2(Tout(2) - C_arc(2), Tout(1) - C_arc(1));

            arc_valid = true;
            line_end = Tin;
        end
    end
end

line_vec = line_end - A;
line_len = sqrt(line_vec(1)^2 + line_vec(2)^2);
if line_len < 1e-6
    line_len = 1e-6;
end

rel_A = p_xy - A;
s_line = rel_A(1) * t1(1) + rel_A(2) * t1(2);
e_ct = -rel_A(1) * t1(2) + rel_A(2) * t1(1);

% 고도 목표는 현재 segment 끝 waypoint 기준 유지
tgt_z = WP(seg_idx + 1, 3);
h_ref = -tgt_z;

%% ========== 2. Primitive manager ==========
if ~arc_valid
    path_mode = 0;
end

if path_mode == 0
    % LINE -> ARC 진입: Tin 직전에서만 전환
    if arc_valid && (s_line >= line_len - arc_entry_margin)
        path_mode = 1;
    end
else
    % ARC -> 다음 LINE 전환: Tout 통과로만 wp_idx 증가
    s_after_tout = 0.0;
    e_out = 0.0;
    if arc_valid
        t2 = (WP(seg_idx + 2, 1:2).' - B);
        L2_tmp = sqrt(t2(1)^2 + t2(2)^2);
        if L2_tmp < 1e-6
            L2_tmp = 1e-6;
        end
        t2 = t2 / L2_tmp;
        s_after_tout = (p_xy(1) - Tout(1)) * t2(1) + (p_xy(2) - Tout(2)) * t2(2);
        e_out = -(p_xy(1) - Tout(1)) * t2(2) + (p_xy(2) - Tout(2)) * t2(1);
    end

    if arc_valid && (s_after_tout >= 0.0) && (abs(e_out) <= arc_exit_lat_tol)
        wp_idx = min(wp_idx + 1, N_wp - 1);
        path_mode = 0;

        % 새 segment로 재계산
        seg_idx = max(min(wp_idx, N_wp - 1), 1);
        A = WP(seg_idx,     1:2).';
        B = WP(seg_idx + 1, 1:2).';

        v1 = B - A;
        L1 = sqrt(v1(1)^2 + v1(2)^2);
        if L1 < 1e-6
            L1 = 1e-6;
        end
        t1 = v1 / L1;

        arc_valid = false;
        line_end = B;

        if seg_idx < N_wp - 1
            Cpt = WP(seg_idx + 2, 1:2).';
            v2 = Cpt - B;
            L2 = sqrt(v2(1)^2 + v2(2)^2);
            if L2 < 1e-6
                L2 = 1e-6;
            end
            t2 = v2 / L2;

            dot12 = t1(1) * t2(1) + t1(2) * t2(2);
            dot12 = min(max(dot12, -1.0), 1.0);
            delta = acos(dot12);
            turn_z = t1(1) * t2(2) - t1(2) * t2(1);

            if abs(turn_z) > 1e-3 && delta > 5 * pi/180 && delta < 175 * pi/180
                d_nom = R_fillet * tan(delta / 2);
                d_use = min(d_nom, 0.45 * L1);
                d_use = min(d_use, 0.45 * L2);

                if d_use > 0.05
                    R_use = d_use / tan(delta / 2);
                    if turn_z >= 0
                        turn_dir = 1.0;
                    else
                        turn_dir = -1.0;
                    end

                    Tin = B - d_use * t1;
                    Tout = B + d_use * t2;

                    n1_left = [-t1(2); t1(1)];
                    C_arc = Tin + turn_dir * R_use * n1_left;

                    alpha_in = atan2(Tin(2)  - C_arc(2), Tin(1)  - C_arc(1));
                    alpha_out = atan2(Tout(2) - C_arc(2), Tout(1) - C_arc(1));

                    arc_valid = true;
                    line_end = Tin;
                end
            end
        end

        line_vec = line_end - A;
        line_len = sqrt(line_vec(1)^2 + line_vec(2)^2);
        if line_len < 1e-6
            line_len = 1e-6;
        end

        rel_A = p_xy - A;
        s_line = rel_A(1) * t1(1) + rel_A(2) * t1(2);
        e_ct = -rel_A(1) * t1(2) + rel_A(2) * t1(1);

        tgt_z = WP(seg_idx + 1, 3);
        h_ref = -tgt_z;
    end
end

%% ========== 3. Guidance ==========
look_dist = max(min(T_look * max(u_meas, 0.4), L_look_max), L_look_min);

if path_mode == 0
    % LINE primitive: A -> Tin (또는 최종 B)
    s_proj = min(max(s_line, 0.0), line_len);
    look_s = min(s_proj + look_dist, line_len);

    look_x = A(1) + look_s * t1(1);
    look_y = A(2) + look_s * t1(2);

    psi_path = atan2(t1(2), t1(1));
    psi_ct = atan2(-K_ct * e_ct, look_dist);
    psi_desired = atan2(sin(psi_path + psi_ct), cos(psi_path + psi_ct));

    % 코너 직전에는 ARC 진입 전에 미리 감속해야 yaw rate 요구를 맞출 수 있습니다.
    if arc_valid && (s_proj >= max(line_len - arc_slow_margin, 0.0))
        u_ref = u_corner;
    else
        u_ref = u_cruise;
    end

else
    % ARC primitive: Tin -> Tout on circle centered at C_arc
    rel_C = p_xy - C_arc;
    alpha_pos = atan2(rel_C(2), rel_C(1));
    r_pos = sqrt(rel_C(1)^2 + rel_C(2)^2);

    if turn_dir > 0
        ang_total = mod(alpha_out - alpha_in, 2 * pi);
        ang_prog = mod(alpha_pos - alpha_in, 2 * pi);
    else
        ang_total = mod(alpha_in - alpha_out, 2 * pi);
        ang_prog = mod(alpha_in - alpha_pos, 2 * pi);
    end

    % Tin 이전에서는 progress=0으로 고정
    s_from_tin = (p_xy(1) - Tin(1)) * t1(1) + (p_xy(2) - Tin(2)) * t1(2);
    if s_from_tin < 0.0
        ang_prog = 0.0;
    end

    ang_prog = min(max(ang_prog, 0.0), ang_total);
    ang_look = min(ang_prog + look_dist / max(R_use, 1e-6), ang_total);

    alpha_cmd = alpha_in + turn_dir * ang_look;
    psi_tan = alpha_cmd + turn_dir * pi / 2;
    r_err = r_pos - R_use;
    psi_rad_corr = atan2(K_arc_radial * r_err, max(look_dist, 0.2));
    psi_desired = atan2(sin(psi_tan - turn_dir * psi_rad_corr), ...
                        cos(psi_tan - turn_dir * psi_rad_corr));
    u_ref = u_corner;
end

% psi_ref rate limiting
psi_err_raw = atan2(sin(psi_desired - prev_psi_ref), cos(psi_desired - prev_psi_ref));
dpsi = min(max(psi_err_raw, -psi_rate_max * dt), psi_rate_max * dt);
psi_ref = prev_psi_ref + dpsi;
psi_ref = atan2(sin(psi_ref), cos(psi_ref));
prev_psi_ref = psi_ref;

% heading error
psi_err = atan2(sin(psi_ref - psi), cos(psi_ref - psi));

%% ========== 4. Speed Controller (PI) ==========
u_err = u_ref - u_meas;
u_integral = u_integral + u_err * dt;
u_integral = min(max(u_integral, -1.0), 3.0);

tail_freq = Kp_u * u_err + Ki_u * u_integral;
tail_freq = min(max(tail_freq, freq_min), freq_max);
tail_freq = max(tail_freq, 1.1);  % altitude hold floor

%% ========== 5. Altitude ==========
h_err = h_ref - height;
hdot = (height - prev_height) / dt; %#ok<NASGU>
prev_height = height;

% 5a. Tail pitch (primary)
F_thr_est = rho_air * pi^2 * S_tail_area * tail_amp_nom^2 * tail_freq^2 * C_T;
F_thr_est = max(F_thr_est, 0.001);
tail_pitch_ff = -asin(min(max(F_neg_buoy / F_thr_est, -0.4), 0.4));
tail_pitch_fb = -(Kp_h_tail * h_err);
tail_pitch_cmd = tail_pitch_ff + tail_pitch_fb;
tail_pitch_cmd = min(max(tail_pitch_cmd, -tail_pitch_max), tail_pitch_max);

% 5b. Pec common (secondary)
u_eff = max(u_meas, 0.65);
pec_ff = F_neg_buoy / (rho_air * u_eff^2 * S_pec * CL_alpha) * 0.5;
pec_fb = Kp_h_pec * h_err;
pec_common = pec_ff + pec_fb;
pec_common = min(max(pec_common, -pec_common_max), pec_common_max);

%% ========== 6. Bank Turn ==========
phi_bank = K_bank * psi_err;
phi_bank = min(max(phi_bank, -phi_max), phi_max);
if u_meas < 0.7
    phi_bank = 0.0;
end

%% ========== 출력 ==========
Ref_Att_Auto = [phi_bank; 0; psi_ref];
TailFreq_Auto = tail_freq;
PecCommon_Auto = pec_common;
TailPitch_Auto = tail_pitch_cmd;

if seg_idx == N_wp - 1
    dist_to_final = sqrt((x - WP(N_wp, 1))^2 + (y - WP(N_wp, 2))^2); %#ok<NASGU>
    wp_idx_out = N_wp;
else
    wp_idx_out = min(wp_idx + 1, N_wp);
end

end
