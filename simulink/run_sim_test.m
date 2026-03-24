%% run_sim_test.m — 0.50m 직경, -1g 음성부력 시뮬레이션 테스트
% MATLAB 커맨드 창에서 실행하세요: run('run_sim_test.m')

run('init_dolphin_params.m');
mdl = 'DolphinDrone';
if ~bdIsLoaded(mdl), load_system(mdl); end

%% Simulink MATLAB Function 블록 코드 업데이트
rt = sfroot;
chart = rt.find('-isa','Stateflow.EMChart','Path',[mdl '/ForceCalc']);
if ~isempty(chart)
    % ForceCalc_code.m에서 읽어서 행벡터 변환 적용
    code = fileread('ForceCalc_code.m');
    % 6DoF 블록은 행벡터(1x3)를 요구하므로 출력 transpose
    code = strrep(code, 'Forces = zeros(3,1);', 'Forces = zeros(1,3);');
    code = strrep(code, 'Torques = zeros(3,1);', 'Torques = zeros(1,3);');
    code = strrep(code, ...
        'Forces  = F_buoy_b + F_grav_b + F_tail + [0; 0; Fz_pec] + F_drag;', ...
        'Forces  = (F_buoy_b + F_grav_b + F_tail + [0; 0; Fz_pec] + F_drag)'';');
    code = strrep(code, ...
        'Torques = T_buoy + T_tail + [T_roll_pec; T_pitch_pec; 0] + T_dorsal + T_rot_damp;', ...
        'Torques = (T_buoy + T_tail + [T_roll_pec; T_pitch_pec; 0] + T_dorsal + T_rot_damp)'';');
    chart.Script = code;
    fprintf('ForceCalc 블록 코드 업데이트 완료\n');
end

%% 6DoF 파라미터 업데이트
set_param([mdl '/SixDOF'], ...
    'Mass', sprintf('%.6f', body.m_total), ...
    'Inertia', sprintf('[%.6f 0 0; 0 %.6f 0; 0 0 %.6f]', body.Jxx, body.Jyy, body.Jzz), ...
    'xme_0', '[0, 0, -1.5]', ...
    'eul_0', '[0.087, 0.052, 0]');  % roll=5deg, pitch=3deg 초기교란

%% 시뮬레이션 실행
set_param(mdl, 'StopTime', '20');
save_system(mdl);

fprintf('\n시뮬레이션 시작...\n');
simOut = sim(mdl);

%% 결과 출력
pos = simOut.pos_log.Data;
eul = simOut.euler_log.Data;
vel = simOut.vel_log.Data;
N = size(eul,1);

fprintf('\n=== 0.50m 직경 / -1g 음성부력 시뮬레이션 결과 ===\n');
fprintf('체적: %.4f m³\n', body.V_envelope);
fprintf('중성부력질량: %.1f g\n', body.m_neutral*1000);
fprintf('총질량: %.1f g\n', body.m_total*1000);
fprintf('음성부력: %.1f g\n', body.m_eff*1000);
fprintf('\nt=0s:  자세 [%.2f, %.2f, %.2f] deg\n', rad2deg(eul(1,:)));
fprintf('t=5s:  자세 [%.2f, %.2f, %.2f] deg\n', rad2deg(eul(round(N*5/20),:)));
fprintf('t=10s: 자세 [%.2f, %.2f, %.2f] deg\n', rad2deg(eul(round(N*10/20),:)));
fprintf('t=20s: 자세 [%.2f, %.2f, %.2f] deg\n', rad2deg(eul(N,:)));
fprintf('\n최종 위치(NED): [%.2f, %.2f, %.2f] m\n', pos(N,:));
fprintf('최종 높이(up): %.2f m\n', -pos(N,3));
fprintf('최종 속도(body): [%.3f, %.3f, %.3f] m/s\n', vel(N,:));

%% 그래프
figure('Position',[100 100 900 700]);
t = simOut.euler_log.Time;
data = rad2deg(eul);

subplot(3,1,1);
plot(t, data(:,1), 'b', 'LineWidth', 1.5);
hold on; yline(0, 'r--'); hold off;
ylabel('Roll (deg)'); title('0.50m / -1g 음성부력 / 자세 응답');
grid on; xlim([0 20]);

subplot(3,1,2);
plot(t, data(:,2), 'r', 'LineWidth', 1.5);
hold on; yline(0, 'r--'); hold off;
ylabel('Pitch (deg)');
grid on; xlim([0 20]);

subplot(3,1,3);
plot(t, data(:,3), 'Color', [0.2 0.7 0.2], 'LineWidth', 1.5);
hold on; yline(0, 'r--'); hold off;
ylabel('Yaw (deg)'); xlabel('Time (s)');
grid on; xlim([0 20]);

saveas(gcf, 'attitude_050m_neg1g.png');
fprintf('\n그래프 저장: attitude_050m_neg1g.png\n');
