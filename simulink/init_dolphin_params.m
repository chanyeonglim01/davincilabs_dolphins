%% init_dolphin_params.m
% 돌고래 헬륨 드론 물리 파라미터 초기화 스크립트
% Simulink 모델 실행 전 반드시 실행할 것

%% ========== 환경 파라미터 ==========
env.rho_air = 1.225;        % 공기 밀도 [kg/m³] (20°C, 해수면)
env.rho_He  = 0.164;        % 헬륨 밀도 [kg/m³] (20°C)
env.g       = 9.81;         % 중력 가속도 [m/s²]

%% ========== 기체 파라미터 ==========
body.length     = 2.0;          % 전체 길이 [m]
body.max_diam   = 0.50;         % 최대 직경 [m] (0.58→0.50 재설계)
body.a_semi     = body.length / 2;
body.b_semi     = body.max_diam / 2;
body.V_envelope = (4/3) * pi * body.a_semi * body.b_semi^2;
                                % Prolate spheroid 체적 [m^3]
                                % 2.0 m x 0.58 m -> 약 0.352 m^3

body.m_neutral  = (env.rho_air - env.rho_He) * body.V_envelope;
                                % 중성부력 질량 [kg]
body.buoyancy_margin = -0.0005; % 음성부력 마진 [kg] (약 -0.5 g)
body.m_total    = body.m_neutral - body.buoyancy_margin;
                                % 총 질량 [kg] (m_neutral + 0.001)
body.m_eff      = body.m_total - body.m_neutral;
                                % 정적 질량 불균형 [kg]
                                % > 0 이면 음성부력 (하강)

body.F_buoy_nom   = body.m_neutral * env.g;
body.F_weight_nom = body.m_total * env.g;
body.Fz_trim_nom  = body.F_weight_nom - body.F_buoy_nom;
                                % NED 기준 정적 Z힘 [N]
                                % < 0 이면 정지 시 약한 상승

% 관성 모멘트 (타원체 근사)
body.Jxx = (1/5) * body.m_total * (body.b_semi^2 + body.b_semi^2);
body.Jyy = (1/5) * body.m_total * (body.a_semi^2 + body.b_semi^2);
body.Jzz = body.Jyy;
body.J   = diag([body.Jxx, body.Jyy, body.Jzz]);

% 무게중심(CG) - 부력중심(CB) 오프셋
body.r_CB_CG = [0; 0; -0.05];  % CB가 CG보다 5cm 위 [m], NED z-down

%% ========== 공기역학 파라미터 ==========
aero.Cd      = 0.30;        % 등가 형상 항력계수 (엔벨로프+지느러미 포함)
aero.S_ref   = pi * body.b_semi^2;
                            % 기준 면적 [m²] (정면 단면적)

%% ========== 꼬리지느러미 (Caudal Fin) ==========
tail.S_fin      = 0.020;    % 꼬리 면적 [m²]
tail.C_T        = 0.30;     % 추력계수
tail.r_tail     = [-0.80; 0; 0]; % 꼬리 위치 (기체 좌표계, 후방) [m]
tail.f_min      = 0.5;      % 최소 진동 주파수 [Hz]
tail.f_max      = 3.0;      % 최대 진동 주파수 [Hz]
tail.A_min      = 0.17;     % 최소 진폭 [rad] (≈10°)
tail.A_max      = 0.70;     % 최대 진폭 [rad] (≈40°)
tail.yaw_max    = 0.52;     % 최대 Yaw 편향 [rad] (≈30°)

%% ========== 가슴지느러미 (Pectoral Fins) ==========
pec.S_fin       = 0.010;    % 가슴지느러미 면적 (한쪽) [m²]
pec.C_L_alpha   = 2*pi;     % 양력 기울기 [1/rad] (평판 이론)
pec.r_pec       = [0.10; 0.25; -0.05]; % 가슴지느러미 위치 [m]
pec.delta_max   = deg2rad(35);  % 최대 편향 [rad]
pec.alpha_stall = deg2rad(15);  % 선형영역 종료 [rad]
pec.C_L_max     = 1.2;          % stall 이후 양력 포화
pec.V_min       = 0.05;         % 저속 surrogate용 최소 유속 [m/s]

%% ========== 등지느러미 (Dorsal Fin) — 고정 수동 안정판 ==========
dorsal.S_fin        = 0.015;    % 등지느러미 면적 [m²]
dorsal.C_damp_yaw   = 0.005;   % Yaw 감쇠계수 [N·m·s/rad]
dorsal.C_damp_roll  = 0.003;   % Roll 감쇠계수 [N·m·s/rad]
dorsal.r_dorsal     = [0.10; 0; 0.25]; % 등지느러미 위치 (상부) [m]

%% ========== 서보 모터 ==========
servo.tau = 0.05;           % 서보 시정수 [s] (1차 지연)
servo.rate_limit = 10.0;    % 서보 각속도 한계 [rad/s]

%% ========== 제어기 파라미터 (PID) ==========
% --- 내부 루프: 자세 제어 (ESP32, 100Hz) ---
ctrl_att.Ts = 0.01;         % 샘플링 시간 [s] (100 Hz)

% Roll PID
ctrl_att.Kp_roll = 2.0;
ctrl_att.Ki_roll = 0.1;
ctrl_att.Kd_roll = 0.5;

% Pitch PID
ctrl_att.Kp_pitch = 2.0;
ctrl_att.Ki_pitch = 0.1;
ctrl_att.Kd_pitch = 0.5;

% Yaw PID
ctrl_att.Kp_yaw = 1.5;
ctrl_att.Ki_yaw = 0.05;
ctrl_att.Kd_yaw = 0.3;

% --- 외부 루프: 위치 제어 (PC, 20Hz) ---
ctrl_pos.Ts = 0.05;         % 샘플링 시간 [s] (20 Hz)

% X (전진) PID
ctrl_pos.Kp_x = 1.0;
ctrl_pos.Ki_x = 0.05;
ctrl_pos.Kd_x = 0.8;

% Y (횡) PID
ctrl_pos.Kp_y = 1.0;
ctrl_pos.Ki_y = 0.05;
ctrl_pos.Kd_y = 0.8;

% Z (고도) PID
ctrl_pos.Kp_z = 1.5;
ctrl_pos.Ki_z = 0.2;
ctrl_pos.Kd_z = 0.5;

%% ========== 시뮬레이션 설정 ==========
sim_params.T_end = 60;          % 시뮬레이션 시간 [s]
sim_params.dt    = 0.001;       % 고정 스텝 [s] (1kHz)

% 초기 조건
sim_params.pos_init    = [0; 0; 1.5];   % 초기 위치 [m] (x,y,z)
sim_params.vel_init    = [0; 0; 0];     % 초기 속도 [m/s]
sim_params.euler_init  = [0; 0; 0];     % 초기 자세 [rad] (roll,pitch,yaw)
sim_params.omega_init  = [0; 0; 0];     % 초기 각속도 [rad/s]

% 목표 위치 (Waypoints)
sim_params.waypoints = [
    0,  0, 0, 1.5;    % t=0s:  시작점
    10, 2, 0, 1.5;    % t=10s: 전진
    20, 2, 2, 2.0;    % t=20s: 횡이동 + 상승
    30, 0, 2, 2.0;    % t=30s: 후진
    40, 0, 0, 1.5;    % t=40s: 복귀
];

fprintf('돌고래 헬륨 드론 파라미터 초기화 완료\n');
fprintf('  체적: %.3f m^3\n', body.V_envelope);
fprintf('  중성부력 질량: %.1f g\n', body.m_neutral * 1000);
fprintf('  총 질량: %.1f g\n', body.m_total * 1000);
fprintf('  양성부력 마진: %.1f g\n', body.buoyancy_margin * 1000);
fprintf('  정적 Z힘 (NED, +down): %.3f N\n', body.Fz_trim_nom);
