%% create_dolphin_model.m
% 돌고래 헬륨 드론 Simulink 모델 자동 생성 스크립트

%% 파라미터 로드
run('init_dolphin_params.m');

%% 기존 모델 정리
modelName = 'DolphinDrone';
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if exist([modelName '.slx'], 'file')
    delete([modelName '.slx']);
end

%% 새 모델 생성
new_system(modelName);
open_system(modelName);

% 솔버 설정
set_param(modelName, 'Solver', 'ode4');
set_param(modelName, 'FixedStep', num2str(sim_params.dt));
set_param(modelName, 'StopTime', num2str(sim_params.T_end));

%% ================================================================
%  Plant 서브시스템
%% ================================================================
plantPath = [modelName '/Plant'];
add_block('simulink/Ports & Subsystems/Subsystem', plantPath);
delete_line(plantPath, 'In1/1', 'Out1/1');
delete_block([plantPath '/In1']);
delete_block([plantPath '/Out1']);

% --- 입력 포트 ---
inNames = {'tail_freq','tail_amp','tail_yaw','pec_left','pec_right'};
for i = 1:length(inNames)
    add_block('simulink/Sources/In1', [plantPath '/' inNames{i}]);
    set_param([plantPath '/' inNames{i}], 'Port', num2str(i));
    set_param([plantPath '/' inNames{i}], 'Position', [30, 30+60*(i-1), 60, 50+60*(i-1)]);
end

% --- Clock (시간) ---
add_block('simulink/Sources/Clock', [plantPath '/Clock']);
set_param([plantPath '/Clock'], 'Position', [30, 400, 60, 420]);

% --- Mux: 서보 입력 5개를 하나로 ---
add_block('simulink/Signal Routing/Mux', [plantPath '/ServoMux']);
set_param([plantPath '/ServoMux'], 'Inputs', '5');
set_param([plantPath '/ServoMux'], 'Position', [120, 30, 125, 310]);
for i = 1:5
    add_line(plantPath, [inNames{i} '/1'], ['ServoMux/' num2str(i)]);
end

% --- MATLAB Function: 힘/토크 계산 ---
add_block('simulink/User-Defined Functions/MATLAB Function', [plantPath '/ForceCalc']);
set_param([plantPath '/ForceCalc'], 'Position', [200, 100, 380, 350]);

% MATLAB Function 스크립트 설정
fcnBlock = [plantPath '/ForceCalc'];
rt = sfroot;
chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', fcnBlock);
if ~isempty(chart)
    chart.Script = sprintf([...
        'function [Forces, Torques] = ForceCalc(servo_in, Vb, euler_angles, omega_b, t)\n' ...
        '%%#codegen\n' ...
        '%% 돌고래 헬륨 드론 힘/토크 계산\n' ...
        '%% servo_in: [tail_freq, tail_amp, tail_yaw, pec_left, pec_right]\n' ...
        '%% Vb: [u,v,w] body velocity\n' ...
        '%% euler_angles: [phi,theta,psi]\n' ...
        '%% omega_b: [p,q,r]\n\n' ...
        'Forces = zeros(3,1);\n' ...
        'Torques = zeros(3,1);\n\n' ...
        '%% 파라미터\n' ...
        'rho_air = 1.225; rho_He = 0.164; g = 9.81;\n' ...
        'V_env = 0.35; m_total = 0.50;\n' ...
        'S_tail = 0.02; C_T = 0.30;\n' ...
        'S_pec = 0.01; CL_alpha = 2*pi;\n' ...
        'Cd = 0.04; S_ref = 0.15;\n' ...
        'C_damp_yaw = 0.005; C_damp_roll = 0.003;\n' ...
        'r_CB_CG = [0; 0; 0.05];\n' ...
        'r_tail_x = -0.80; r_pec_y = 0.25; r_pec_x = 0.10;\n\n' ...
        '%% 서보 입력 분리\n' ...
        'tail_freq = servo_in(1);\n' ...
        'tail_amp = servo_in(2);\n' ...
        'tail_yaw_cmd = servo_in(3);\n' ...
        'pec_left = servo_in(4);\n' ...
        'pec_right = servo_in(5);\n\n' ...
        'phi = euler_angles(1); theta = euler_angles(2); psi = euler_angles(3);\n' ...
        'u = Vb(1); v = Vb(2); w = Vb(3);\n' ...
        'V_mag = sqrt(u^2 + v^2 + w^2);\n' ...
        'p = omega_b(1); q = omega_b(2); r = omega_b(3);\n\n' ...
        '%% 1. DCM (Earth->Body)\n' ...
        'cphi = cos(phi); sphi = sin(phi);\n' ...
        'cth = cos(theta); sth = sin(theta);\n' ...
        'cpsi = cos(psi); spsi = sin(psi);\n' ...
        'R = [cth*cpsi, cth*spsi, -sth;\n' ...
        '     sphi*sth*cpsi-cphi*spsi, sphi*sth*spsi+cphi*cpsi, sphi*cth;\n' ...
        '     cphi*sth*cpsi+sphi*spsi, cphi*sth*spsi-sphi*cpsi, cphi*cth];\n\n' ...
        '%% 2. 부력 (NED: Z하향, 부력은 -Z)\n' ...
        'F_buoy_e = [0; 0; -(rho_air - rho_He)*V_env*g];\n' ...
        'F_buoy_b = R * F_buoy_e;\n' ...
        'T_buoy = cross(r_CB_CG, F_buoy_b);\n\n' ...
        '%% 3. 중력 (NED: +Z)\n' ...
        'F_grav_e = [0; 0; m_total*g];\n' ...
        'F_grav_b = R * F_grav_e;\n\n' ...
        '%% 4. 꼬리 추진\n' ...
        'F_thr = rho_air * pi^2 * S_tail * tail_amp^2 * tail_freq^2 * C_T;\n' ...
        'F_tail = [F_thr*cos(tail_yaw_cmd); F_thr*sin(tail_yaw_cmd); 0];\n' ...
        'T_tail = [0; 0; F_thr*sin(tail_yaw_cmd)*abs(r_tail_x)];\n\n' ...
        '%% 5. 가슴지느러미\n' ...
        'V_eff = max(V_mag, 0.1);\n' ...
        'F_pL = 0.5*rho_air*V_eff^2*S_pec*CL_alpha*pec_left;\n' ...
        'F_pR = 0.5*rho_air*V_eff^2*S_pec*CL_alpha*pec_right;\n' ...
        'Fz_pec = -(F_pL + F_pR)*0.5;\n' ...
        'T_roll = (F_pL - F_pR)*r_pec_y;\n' ...
        'T_pitch = (F_pL + F_pR)*0.5*r_pec_x;\n\n' ...
        '%% 6. 등지느러미 수동 감쇠\n' ...
        'T_dorsal = [-C_damp_roll*p; 0; -C_damp_yaw*r];\n\n' ...
        '%% 7. 공기 항력\n' ...
        'if V_mag > 0.001\n' ...
        '    F_drag = -0.5*rho_air*Cd*S_ref*V_mag*Vb;\n' ...
        'else\n' ...
        '    F_drag = [0;0;0];\n' ...
        'end\n\n' ...
        '%% 합산\n' ...
        'Forces = F_buoy_b + F_grav_b + F_tail + [0;0;Fz_pec] + F_drag;\n' ...
        'Torques = T_buoy + T_tail + [T_roll;T_pitch;0] + T_dorsal + (-0.001*omega_b);\n']);
end

% --- 6-DOF 블록 ---
add_block('aerolib6dof/6DoF (Euler Angles)', [plantPath '/SixDOF']);
set_param([plantPath '/SixDOF'], 'Position', [500, 120, 680, 360]);
set_param([plantPath '/SixDOF'], 'Mass', 'body.m_total');
set_param([plantPath '/SixDOF'], 'Inertia', '[body.Jxx, body.Jyy, body.Jzz, 0, 0, 0]');
set_param([plantPath '/SixDOF'], 'xme_0', '[sim_params.pos_init(1), sim_params.pos_init(2), -sim_params.pos_init(3)]');
set_param([plantPath '/SixDOF'], 'Vm_0', '[sim_params.vel_init(1), sim_params.vel_init(2), sim_params.vel_init(3)]');
set_param([plantPath '/SixDOF'], 'eul_0', '[sim_params.euler_init(1), sim_params.euler_init(2), sim_params.euler_init(3)]');
set_param([plantPath '/SixDOF'], 'pm_0', '[sim_params.omega_init(1), sim_params.omega_init(2), sim_params.omega_init(3)]');

% --- Demux: ForceCalc 출력 분리 ---
add_block('simulink/Signal Routing/Demux', [plantPath '/ForceDemux']);
set_param([plantPath '/ForceDemux'], 'Outputs', '2');
set_param([plantPath '/ForceDemux'], 'Position', [420, 180, 425, 300]);

% ForceCalc → Demux → 6DOF
add_line(plantPath, 'ForceCalc/1', 'SixDOF/1');   % Forces → Fb
add_line(plantPath, 'ForceCalc/2', 'SixDOF/2');   % Torques → Mb

% --- 피드백 루프: 6DOF 출력 → ForceCalc 입력 ---
% 6DOF 출력: 1=Ve, 2=Xe, 3=euler, 4=DCM, 5=Vb, 6=pqr, 7=pdot_qdot_rdot

% Vb 피드백 (출력 5)
add_line(plantPath, 'SixDOF/5', 'ForceCalc/2');
% Euler 피드백 (출력 3)
add_line(plantPath, 'SixDOF/3', 'ForceCalc/3');
% pqr 피드백 (출력 6)
add_line(plantPath, 'SixDOF/6', 'ForceCalc/4');

% Servo입력 → ForceCalc
add_line(plantPath, 'ServoMux/1', 'ForceCalc/1');
% Clock → ForceCalc
add_line(plantPath, 'Clock/1', 'ForceCalc/5');

% --- 출력 포트 ---
outNames = {'Position','Euler','Velocity','AngVel'};
outPorts = [2, 3, 5, 6];  % 6DOF 출력 포트 번호
for i = 1:length(outNames)
    add_block('simulink/Sinks/Out1', [plantPath '/' outNames{i}]);
    set_param([plantPath '/' outNames{i}], 'Port', num2str(i));
    set_param([plantPath '/' outNames{i}], 'Position', [780, 80+70*(i-1), 810, 100+70*(i-1)]);
    add_line(plantPath, ['SixDOF/' num2str(outPorts(i))], [outNames{i} '/1']);
end

% Plant 위치
set_param(plantPath, 'Position', [350, 100, 600, 400]);

%% ================================================================
%  입력 소스 (테스트용 Constant)
%% ================================================================
inputDefs = {
    'Tail_Freq', '2.0',  [50,130,150,150];
    'Tail_Amp',  '0.52', [50,180,150,200];
    'Tail_Yaw',  '0.0',  [50,230,150,250];
    'Pec_Left',  '0.0',  [50,280,150,300];
    'Pec_Right', '0.0',  [50,330,150,350];
};

for i = 1:size(inputDefs,1)
    blkName = [modelName '/' inputDefs{i,1}];
    add_block('simulink/Sources/Constant', blkName);
    set_param(blkName, 'Value', inputDefs{i,2});
    set_param(blkName, 'Position', inputDefs{i,3});
    add_line(modelName, [inputDefs{i,1} '/1'], ['Plant/' num2str(i)]);
end

%% ================================================================
%  출력: Scope + To Workspace
%% ================================================================
% Position Scope
add_block('simulink/Sinks/Scope', [modelName '/Position_Scope']);
set_param([modelName '/Position_Scope'], 'Position', [700, 110, 760, 150]);
add_line(modelName, 'Plant/1', 'Position_Scope/1');

% Euler Scope
add_block('simulink/Sinks/Scope', [modelName '/Euler_Scope']);
set_param([modelName '/Euler_Scope'], 'Position', [700, 180, 760, 220]);
add_line(modelName, 'Plant/2', 'Euler_Scope/1');

% Velocity Scope
add_block('simulink/Sinks/Scope', [modelName '/Velocity_Scope']);
set_param([modelName '/Velocity_Scope'], 'Position', [700, 250, 760, 290]);
add_line(modelName, 'Plant/3', 'Velocity_Scope/1');

% AngVel Scope
add_block('simulink/Sinks/Scope', [modelName '/AngVel_Scope']);
set_param([modelName '/AngVel_Scope'], 'Position', [700, 320, 760, 360]);
add_line(modelName, 'Plant/4', 'AngVel_Scope/1');

% To Workspace
add_block('simulink/Sinks/To Workspace', [modelName '/PosLog']);
set_param([modelName '/PosLog'], 'VariableName', 'pos_log');
set_param([modelName '/PosLog'], 'Position', [700, 380, 780, 400]);
add_line(modelName, 'Plant/1', 'PosLog/1');

add_block('simulink/Sinks/To Workspace', [modelName '/EulerLog']);
set_param([modelName '/EulerLog'], 'VariableName', 'euler_log');
set_param([modelName '/EulerLog'], 'Position', [700, 420, 780, 440]);
add_line(modelName, 'Plant/2', 'EulerLog/1');

%% 저장
save_system(modelName);
fprintf('\n=== DolphinDrone.slx 생성 완료 ===\n');
fprintf('위치: %s/%s.slx\n', pwd, modelName);
