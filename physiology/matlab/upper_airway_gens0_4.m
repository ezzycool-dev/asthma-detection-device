%% =========================================================================
% UPPER AIRWAY FLOW & DEAD-SPACE TRANSPORT (GENERATIONS 0-4)  -  v7
% v7: every pressure in mmHg; flow exported as Q_V (L/s); every value traced
%     to the course sources (Guyton, Sys Phys, Brewer & Orr) or a team
%     agreement (VT = 500 mL, 4 s breath). Ryan's lung is a Guyton placeholder.
% Domain: trachea entry (Gen 0) -> exit of Gen 4. Anna owns Gens 5-16,
%         Ryan owns the alveolar system. Nose/mouth are NOT tracked: gas is
%         assumed well mixed and at BTPS on arrival at the trachea.
% v6 change - Q(t) is no longer assumed. It is COUPLED to the alveolar system:
%   breathing muscles lower pleural pressure -> alveolar pressure falls
%   below atmospheric -> air flows in, limited by airway resistance:
%       dV_A/dt = Q
%       L_aw dQ/dt = (P_atm - P_alv) - dP_resist(Q)
%       P_alv = P_pl(t) + P_tp_FRC + (alv_gas_volume - V_FRC)/C_L     (Ryan's system)
%   The sinusoid moves from the FLOW to the PLEURAL PRESSURE (muscle drive),
%   which is the physiological cause. flow_mode = 'sinusoid' still gives the
%   old imposed flow for comparison.
% Extrathoracic resistance (nose/mouth/pharynx/larynx): Rohrer form
%   dP = K1 Q + K2 Q^2 (Sys Phys Eqn 6.2.10), K1 calibrated so the whole
%   airway gives Guyton's -1 cmH2O alveolar pressure for 0.5 L in 2 s.
%   Gas in that region is still not tracked; only its pressure drop is used.
% Units: every pressure you set, see or export is in mmHg (team convention);
%        flows in L/s (Q_V); concentrations in mol/m^3 (= mmol/L). The physics
%        converts to SI (Pa, m^3) internally once, because mu_air and r_gas are SI.
% =========================================================================
clear; clc;


%% 1. CONSTANTS (every number the model uses lives here)
% Every value comes from a course source (named in its comment) or a team
% agreement. Pressures are in mmHg; an SI copy is made only where the
% physics needs Pa or m^3.
mmHg       = 133.322;        % [Pa per mmHg]
cmH2O      = 98.0665;        % [Pa per cmH2O] (Guyton reports lung pressures in cmH2O)
p_atm      = 760;            % [mmHg] atmospheric pressure at sea level (Guyton)
p_atm_pa   = p_atm * mmHg;   % [Pa]   SI copy, used by the physics
p_h2o_body = 47;             % [mmHg] water vapour pressure at 37 C (Guyton Ch. 39)
f_io2      = 0.21;           % [-]    fraction of inspired O2 in dry air (Guyton Tbl 39-1: 20.84%)
rho_air    = 1.13;           % [kg/m^3 = g/L] air density at body temp (Sys Phys)
mu_air     = 19.1e-6;        % [Pa s] viscosity of air at 37 C, taken
                             %   directly from Sys Phys Ch. 6.2 ("19.1 x 10^-6 Pa s").
r_gas      = 8.314;          % [J/(mol K)] ideal gas constant
t_body     = 310.15;         % [K] normal body temperature (37 C)

compliance_factor = 2e-5;   % [1/Pa] fractional airway-area change per Pa
use_pedley        = true;   % Pedley entrance-flow correction on/off

dead_space_fraction = 0.3;     % [-]   measured_dead_space_vol = 0.3*tidal_volume
                               %       (150 mL at 500 mL; Guyton Ch. 37: ~150 mL)
extrathoracic_vol   = 72e-6;   % [m^3] nose/mouth/pharynx/larynx share of VD

num_gens  = 5;     % Gens 0-4 handled here
n_seg     = 30;    % number of well-mixed gas segments in my dead space
n_breaths = 3;     % breaths simulated to reach periodic steady state

% Weibel human model A, Gens 0-23 [cm], as tabulated in Murayama et al.,
% J Drug Deliv 2019, Table 1 (doi:10.1155/2019/3921426)
weibel_d_cm = [1.80 1.22 0.83 0.56 0.45 0.35 0.28 0.23 0.186 0.154 0.130 0.109 ...
               0.095 0.082 0.074 0.066 0.060 0.054 0.050 0.047 0.045 0.043 0.041 0.041];
weibel_l_cm = [12.0 4.76 1.90 0.76 1.27 1.07 0.90 0.76 0.64 0.54 0.46 0.39 ...
               0.33 0.27 0.23 0.20 0.165 0.141 0.117 0.099 0.083 0.076 0.059 0.050];
               % gen 21 length 0.076 cm per the paper (was 0.070)
last_conducting_gen = 16;      % conducting zone = Gens 0-16

% Gas compositions [mmHg], column order = species
species       = {'o2', 'co2', 'n2', 'h2o'};
gas_species   = struct('o2', 32, 'co2', 44, 'n2', 28, 'h2o', 18);   % [g/mol]
pph_o2  = 149.4;   % [mmHg] partial pressure of humidified O2   (Sys Phys Tbl 6.3.2)
pph_co2 = 0.2;     % [mmHg] partial pressure of humidified CO2  (Sys Phys Tbl 6.3.2)
pph_n2  = 563.3;   % [mmHg] humidified N2 + inert gases         (Sys Phys Tbl 6.3.2)
pph_h20 = 47;      % [mmHg] gaseous H2O                         (Sys Phys Tbl 6.3.2)
p_trach_mmHg  = [pph_o2 pph_co2 pph_n2 pph_h20];  % gas entering the trachea (BTPS)
p_alv_mmHg    = [100   40  573   47.0];  % alveolar gas placeholder until Anna/Ryan

% Breathing
flow_mode = 'coupled';   % 'coupled' (default) | 'sinusoid' | 'matrix'
t_cycle   = 4;           % [s] one breath, AGREED by the team (15 breaths/min)
t_in      = 2;           % [s] inhalation time (Guyton Ch. 37: "the 2 seconds
                         %     required for normal quiet inspiration")
t_out     = t_cycle - t_in;  % [s] exhalation time = 2 s
n_time    = 100;         % time points per breath (output grid)
tidal_volume = 500e-6;   % [m^3] 500 mL, team agreement (Guyton Ch. 37). FIXED in
                         %   every mode; pleural pressure is CALCULATED to deliver it.
VT_tol    = 0.1e-6;      % [m^3] tolerance on VT (0.1 mL)

% ALL PRESSURES BELOW ARE IN mmHg (team convention). Values that a source
% gives in cmH2O are converted once here: 1 cmH2O = 0.7356 mmHg.
cm2mm = cmH2O / mmHg;    % [mmHg per cmH2O] = 0.7356

% Alveolar system (Ryan). Guyton values are placeholders until his arrive.
C_L_mL_per_mmHg = 200 / cm2mm;   % [mL/mmHg] lung compliance: 200 mL/cmH2O
                                 %   (Guyton Ch. 37) = 271.9 mL/mmHg
V_FRC        = 2300e-6;          % [m^3]     functional residual capacity (Guyton Ch. 39)
P_pl_FRC     = -5.0 * cm2mm;     % [mmHg gauge] pleural pressure at FRC = -3.68
                                 %   (Guyton Ch. 37: -5 cmH2O)
P_pl_shape   = [];               % [t (s), 0..1] shape of the muscle drive over one
                                 %   breath; empty = half-cosine rise over t_in,
                                 %   fall over t_out (assumed)
dP_pl        = -2.5 * cm2mm;     % [mmHg] starting guess only - the swing is
                                 %   CALCULATED so that VT = tidal_volume
ryan_file    = 'ryan_alveolar.mat';  % may hold C_L_mL_per_mmHg, V_FRC,
                                     %   P_pl_FRC (mmHg gauge), P_pl_shape

% Anna's Gens 5-16 resistance. Placeholder = same Pedley/Womersley/Poiseuille
% law on Weibel Gens 5-16 until her table arrives.
anna_resistance_file = 'anna_resistance.mat';  % may hold dP_lower_table =
                                               %   [Q_V (L/s, >= 0), dP (mmHg)]

% Extrathoracic (nose/mouth/pharynx/larynx) RESISTANCE - not tracked as gas,
% but its pressure drop is applied between the atmosphere and the trachea.
% Rohrer's law (Sys Phys Eqn 6.2.10): dP = K1*Q_V + K2*Q_V^2  [mmHg, L/s].
% K1 is calibrated so the WHOLE airway reproduces Guyton Ch. 37: alveolar
% pressure ~ -1 cmH2O (= -0.74 mmHg) "is enough to pull 0.5 liter of air
% into the lungs in the 2 seconds".
use_extrathoracic_R = true;
dP_alv_ref  = 1.0 * cm2mm;   % [mmHg] |alveolar pressure| at peak inspiration = 0.74
VT_ref      = 0.5e-3;        % [m^3]  volume inspired in that breath (Guyton)
T_insp_ref  = 2;             % [s]    inspiration time (Guyton)
K2          = 0;             % [mmHg/(L/s)^2] turbulent coefficient; 0 because
                             %   Re < 2000 at rest, so no turbulence (Sys Phys Ch. 6.2)

% SI copies used only inside the physics (viscosity and r_gas are SI)
C_L         = C_L_mL_per_mmHg * 1e-6 / mmHg;   % [m^3/Pa]
P_pl_FRC_pa = P_pl_FRC * mmHg;                 % [Pa gauge]
dP_pl_pa    = dP_pl * mmHg;                    % [Pa]
dP_alv_ref_pa = dP_alv_ref * mmHg;             % [Pa]
K2_si       = K2 * mmHg / 1e-6;                % [Pa s^2/m^6]

% Used only when flow_mode = 'matrix'
flow_file = 'flow_input.mat';    % matrix mode: flow_matrix = [time (s), Q_V (L/s)]
anna_file = 'anna_outputs.mat';  % may hold C_exh = N x 4 [mol/m^3] at Gen-5 entry, same t


%% 2. GEOMETRY OF THE WHOLE CONDUCTING TREE (Gens 0-16)
% Mine = Gens 0-4. Gens 5-16 are used here ONLY as a placeholder for Anna's
% resistance, so the coupled flow sees the whole airway.
[k_all, n_all, d_all, l_all, area_all] = ...
    build_morphometry(weibel_d_cm, weibel_l_cm, last_conducting_gen);
mine     = 1:num_gens;              % rows for Gens 0-4
annas    = num_gens+1:numel(k_all); % rows for Gens 5-16
omega    = 2*pi / t_cycle;          % [rad/s] breathing frequency

vol_all        = area_all .* l_all;
vol_gen0_4     = sum(vol_all(mine));
vol_conducting = sum(vol_all);

[R_pois_par, wom_ratio, L_par] = womersley_terms(d_all, l_all, n_all, ...
    rho_air, mu_air, omega);
L_aw = sum(L_par);   % [Pa s^2/m^3] gas inertance of Gens 0-16

% Airway-tree pressure drop as a function of flow: mine (Gens 0-4) + Anna's (5-16)
dP_mine_fn  = @(Q) sum(resistive_drop(Q, d_all(mine), l_all(mine), n_all(mine), ...
                   R_pois_par(mine), wom_ratio(mine), rho_air, mu_air, use_pedley));
dP_lower_fn = load_anna_resistance(anna_resistance_file, d_all(annas), l_all(annas), ...
                   n_all(annas), R_pois_par(annas), wom_ratio(annas), rho_air, mu_air, use_pedley);
dP_tree_fn  = @(Q) dP_mine_fn(Q) + dP_lower_fn(Q);


%% 2b. EXTRATHORACIC RESISTANCE (calibrated from Guyton, Rohrer form)
if use_extrathoracic_R
    [K1_si, R_total_ref, R_tree_ref, Q_peak_ref] = calibrate_extrathoracic( ...
        dP_alv_ref_pa, VT_ref, T_insp_ref, dP_tree_fn);
    to_mmHg_per_Lps = 1e-3 / mmHg;   % Pa s/m^3 -> mmHg/(L/s)
    fprintf('Extrathoracic R calibration (Guyton: %.2f mmHg moves %.1f L in %.0f s)\n', ...
        dP_alv_ref, VT_ref*1e3, T_insp_ref);
    fprintf('  reference peak flow    = %.3f L/s\n', Q_peak_ref*1e3);
    fprintf('  R_total (whole airway) = %.2f mmHg/(L/s)\n', R_total_ref*to_mmHg_per_Lps);
    fprintf('  R_tree  (Gens 0-16)    = %.2f mmHg/(L/s)\n', R_tree_ref*to_mmHg_per_Lps);
    fprintf('  K1 (nose->larynx)      = %.2f mmHg/(L/s)  (%.0f%% of total)\n\n', ...
        K1_si*to_mmHg_per_Lps, 100*K1_si/R_total_ref);
else
    K1_si = 0;
end
K1 = K1_si * 1e-3 / mmHg;   % [mmHg/(L/s)] laminar coefficient
dP_extra_fn = @(Q) K1_si * Q + K2_si * Q .* abs(Q);   % [Pa] internal, signed with Q


%% 3. BREATHING: FLOW AT THE TRACHEA
switch flow_mode
    case 'coupled'
        [C_L_mL_per_mmHg, V_FRC, P_pl_FRC, P_pl_shape] = load_ryan(ryan_file, ...
            C_L_mL_per_mmHg, V_FRC, P_pl_FRC, P_pl_shape);     % all mmHg-based
        C_L         = C_L_mL_per_mmHg * 1e-6 / mmHg;   % refresh SI copies
        P_pl_FRC_pa = P_pl_FRC * mmHg;
        % VT is fixed (team agreement), so the pleural SWING is the unknown:
        % scale it until the solved tidal volume equals tidal_volume. The system
        % is nearly linear, so 2-3 passes converge.
        for pass = 1:10
            [time, Q, dQdt, alv_gas_volume, P_alv, P_pl] = coupled_breathing(t_in, t_out, n_time, ...
                n_breaths, p_atm_pa, P_pl_FRC_pa, dP_pl_pa, P_pl_shape, C_L, V_FRC, ...
                L_aw, dP_tree_fn, dP_extra_fn);
            VT_now = trapz(time, max(Q, 0));
            if abs(VT_now - tidal_volume) < VT_tol
                break
            end
            dP_pl_pa = dP_pl_pa * tidal_volume / VT_now;
        end
        dP_pl = dP_pl_pa / mmHg;   % [mmHg] calculated pleural swing
    case 'sinusoid'
        % Half-sine in over t_in, half-sine out over t_out; each moves tidal_volume:
        %   integral_0^T (pi VT/(2T)) sin(pi t/T) dt = VT
        time = linspace(0, t_cycle, n_time)';
        Q    = zeros(n_time, 1);
        ins  = time <= t_in;
        Q(ins)  =  (pi*tidal_volume/(2*t_in))  * sin(pi*time(ins)/t_in);
        Q(~ins) = -(pi*tidal_volume/(2*t_out)) * sin(pi*(time(~ins) - t_in)/t_out);
        dQdt = gradient(Q, time);
        alv_gas_volume = []; P_alv = []; P_pl = [];
    case 'matrix'
        S = load(flow_file, 'flow_matrix');
        time = S.flow_matrix(:, 1);  Q = S.flow_matrix(:, 2) * 1e-3;   % L/s -> m^3/s
        dQdt   = gradient(Q, time);
        alv_gas_volume = []; P_alv = []; P_pl = [];
    otherwise
        error('flow_mode must be ''coupled'', ''sinusoid'' or ''matrix''');
end
VT_solved = trapz(time, max(Q, 0));   % [m^3] = tidal_volume to within VT_tol

% Cross-check: humidified O2 from f_io2 (Dalton) vs Sys Phys Table 6.3.2
fprintf('Check: f_io2*(p_atm - p_h2o_body) = %.1f mmHg vs pph_o2 = %.1f mmHg\n', ...
    f_io2*(p_atm - p_h2o_body), pph_o2);

c_inlet   = p_trach_mmHg * mmHg / (r_gas * t_body);      % [mol/m^3] 1 x 4
c_alv     = p_alv_mmHg   * mmHg / (r_gas * t_body);      % [mol/m^3] 1 x 4
C_deep_in = load_anna_exhale(anna_file, time, c_alv);  % [mol/m^3] N x 4


%% 4. DEAD-SPACE SPLIT
[measured_dead_space_vol, V_D_intra, V_D_up, V_D_anna, my_fraction] = split_dead_space( ...
    tidal_volume, dead_space_fraction, extrathoracic_vol, vol_gen0_4, vol_conducting);
V_D_total = measured_dead_space_vol;   % [m^3] 0.3*tidal_volume

fprintf('Flow mode: %s | VT = %.0f mL | peak Q = %.0f mL/s\n', flow_mode, ...
    VT_solved*1e6, max(Q)*1e6);
if ~isempty(P_alv)
    fprintf('Alveolar pressure swing: %.2f to %.2f mmHg (Guyton: about -0.74 to +0.74)\n', ...
        min(P_alv - p_atm_pa)/mmHg, max(P_alv - p_atm_pa)/mmHg);
    fprintf('Pleural pressure CALCULATED for VT = %.0f mL: %.2f to %.2f mmHg\n', ...
        tidal_volume*1e6, max(P_pl)/mmHg, min(P_pl)/mmHg);
    fprintf('  (Guyton: -3.68 to -5.52 mmHg; Sys Phys Fig 6.2.8: -4 to -6 mmHg)\n');
end
fprintf('VD = %.2f*VT = %.1f mL | intrathoracic %.1f mL (fraction %.3f): mine %.1f | Anna %.1f\n\n', ...
    dead_space_fraction, V_D_total*1e6, V_D_intra*1e6, my_fraction, V_D_up*1e6, V_D_anna*1e6);


%% 5. AIRWAY MECHANICS (pressure profile through Gens 0-4)
% Trachea-entry pressure = atmospheric minus the extrathoracic drop.
p_trach = p_atm_pa - dP_extra_fn(Q);            % [Pa] N x 1
[p_node, table_data, peak_idx] = airway_mechanics(time, Q, dQdt, omega, ...
    k_all(mine), n_all(mine), area_all(mine), l_all(mine), p_atm_pa, p_trach, ...
    compliance_factor, rho_air, mu_air, use_pedley);
print_mechanics_table(table_data, Q(peak_idx), p_node(peak_idx, :), mmHg);


%% 6. DEAD-SPACE TRANSPORT (ODE system, one ODE per segment per species)
c_init = repmat(c_alv, n_seg, 1);   % end-expiration: airway full of alveolar gas
[c_gen4, c_trach] = deadspace_transport(time, Q, V_D_up, n_seg, n_breaths, ...
    c_inlet, C_deep_in, c_init);


%% 7. EXPORT TO ANNA (Gen 5) AND RYAN, AND CHECKS
p_in  = p_node(:, end) / mmHg;                % [mmHg] absolute, Gen-4 exit
p_trach_mmHg_out = p_trach / mmHg;            % [mmHg] absolute, trachea entry
C_in  = c_gen4;                               % [mol/m^3] N x 4 (o2 co2 n2 h2o)
pp_in = struct();                             % [mmHg] same gas as partial pressures
for s = 1:4
    pp_in.(species{s}) = C_in(:, s) * r_gas * t_body / mmHg;
end
pco2_trach = c_trach(:, 2) * r_gas * t_body / mmHg;   % [mmHg] capnogram
P_alv_mmHg = P_alv / mmHg;                    % [mmHg] absolute (coupled mode)
P_pl_mmHg  = P_pl  / mmHg;                    % [mmHg] gauge    (coupled mode)
Q_V        = Q * 1e3;                         % [L/s]   volumetric flow rate
dQ_V_dt    = dQdt * 1e3;                      % [L/s^2]

check_ideal_gas(C_in, p_node(:, end), p_atm_pa, r_gas, t_body);

weibel_matrix = build_weibel_matrix(weibel_d_cm, weibel_l_cm, num_gens, numel(weibel_d_cm) - 1);
units = struct('time', 's', 'Q_V', 'L/s (+ = inspiration)', 'dQ_V_dt', 'L/s^2', ...
               'p_in', 'mmHg absolute', ...
               'C_in', 'mol/m^3 (= mmol/L), cols o2 co2 n2 h2o', 'pp_in', 'mmHg', ...
               'measured_dead_space_vol', 'm^3', 'V_D_up', 'm^3', 'V_D_anna', 'm^3', ...
               'alv_gas_volume', 'm^3', 'P_alv_mmHg', 'mmHg absolute', ...
               'P_pl_mmHg', 'mmHg gauge', 'p_trach_mmHg_out', 'mmHg absolute', ...
               'K1', 'mmHg/(L/s)', 'K2', 'mmHg/(L/s)^2', 'dP_pl', 'mmHg');

save('upper_airway_outputs.mat', 'time', 'Q_V', 'dQ_V_dt', 'p_in', 'C_in', 'pp_in', ...
     'species', 'weibel_matrix', 'gas_species', 'measured_dead_space_vol', 'V_D_up', ...
     'V_D_anna', 'alv_gas_volume', 'P_alv_mmHg', 'P_pl_mmHg', 'p_trach_mmHg_out', ...
     'K1', 'K2', 'dP_pl', 'units');
disp('Process Complete: saved "upper_airway_outputs.mat".');


%% 8. PLOTS
plot_dashboard(time, Q, p_node, p_atm_pa, mmHg, pp_in, pco2_trach, table_data, VT_solved, t_in);
if ~isempty(P_alv)
    plot_coupling(time, Q, alv_gas_volume, V_FRC, P_alv, P_pl, p_atm_pa, mmHg);
end


%% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

function [k, n, d, l, area] = build_morphometry(weibel_d_cm, weibel_l_cm, last_gen)
% Weibel symmetric dichotomy, Gens 0..last_gen: n = 2^k tubes per generation.
k    = (0:last_gen)';
n    = 2.^k;
d    = weibel_d_cm(k + 1)' / 100;     % [m]
l    = weibel_l_cm(k + 1)' / 100;     % [m]
area = n .* pi .* (d/2).^2;           % [m^2] total cross-section per generation
end


function [C_L_mL_per_mmHg, V_FRC, P_pl_FRC, P_pl_shape] = load_ryan(ryan_file, ...
    C_L_mL_per_mmHg, V_FRC, P_pl_FRC, P_pl_shape)
% Ryan's alveolar parameters override the Guyton placeholders when supplied.
% Units in his file: C_L_mL_per_mmHg [mL/mmHg], V_FRC [m^3], P_pl_FRC [mmHg gauge].
% P_pl_shape = [t (s), s(t)] with s = 0 at FRC and s = 1 at the deepest point;
% only its SHAPE is used - its size is calculated so that VT = tidal_volume.
if isfile(ryan_file)
    S = load(ryan_file);
    if isfield(S, 'C_L_mL_per_mmHg'), C_L_mL_per_mmHg = S.C_L_mL_per_mmHg; end
    if isfield(S, 'V_FRC'),      V_FRC      = S.V_FRC;      end
    if isfield(S, 'P_pl_FRC'),   P_pl_FRC   = S.P_pl_FRC;   end
    if isfield(S, 'P_pl_shape'), P_pl_shape = S.P_pl_shape; end
    fprintf('Alveolar parameters loaded from %s\n', ryan_file);
else
    fprintf('No %s found - using Guyton placeholders for the alveolar system\n', ryan_file);
end
end


function dP_lower_fn = load_anna_resistance(anna_resistance_file, d, l, n, ...
    R_pois_par, wom_ratio, rho, mu, use_pedley)
% Pressure drop across Anna's Gens 5-16 as a function of flow, returned in Pa
% for the internal physics. Her table dP_lower_table = [Q_V (L/s, >= 0),
% dP (mmHg)] is used when supplied (same drop in both directions, sign
% follows Q); otherwise a placeholder with the same law as my generations.
mmHg = 133.322;
if isfile(anna_resistance_file)
    S = load(anna_resistance_file, 'dP_lower_table');
    T = S.dP_lower_table;
    dP_lower_fn = @(Q) sign(Q) .* interp1(T(:, 1), T(:, 2), abs(Q) * 1e3, ...
                                          'linear', 'extrap') * mmHg;
    fprintf('Gens 5-16 resistance loaded from %s\n', anna_resistance_file);
else
    dP_lower_fn = @(Q) sum(resistive_drop(Q, d, l, n, R_pois_par, wom_ratio, ...
                                          rho, mu, use_pedley));
    fprintf('No %s found - placeholder resistance for Gens 5-16\n', anna_resistance_file);
end
end


function [R_pois_par, wom_ratio, L_par] = womersley_terms(d, l, n, rho, mu, omega)
% Flow-independent parts of each generation's impedance (n tubes in parallel).
r          = d / 2;
Wo         = r .* sqrt(rho * omega / mu);
R_pois     = 8 * mu .* l ./ (pi * r.^4);            % one tube
Lam        = Wo * 1i^(3/2);
F10        = 2 * besselj(1, Lam) ./ (Lam .* besselj(0, Lam));
Z          = 1i * omega * rho .* l ./ (pi * r.^2) ./ (1 - F10);
wom_ratio  = real(Z) ./ R_pois;                     % Womersley R / Poiseuille R
R_pois_par = R_pois ./ n;                           % generation (parallel) values
L_par      = imag(Z) / omega ./ n;
end


function dP = resistive_drop(Q, d, l, n, R_pois_par, wom_ratio, rho, mu, use_pedley)
% Viscous pressure drop across each generation for flow Q (signed) [Pa].
A     = n .* pi .* (d/2).^2;
Re    = rho * (abs(Q) ./ A) .* d / mu;
ped   = 0.327 * sqrt(Re .* d ./ l);
if use_pedley
    ratio = max(max(wom_ratio, ped), 1);
else
    ratio = wom_ratio;
end
dP = R_pois_par .* ratio * Q;
end


function P = pleural_pressure(t, t_in, t_out, P_pl_FRC, dP_pl, P_pl_shape)
% Muscle drive [Pa gauge] = P_pl_FRC + dP_pl * s(t), with s from 0 (FRC) to 1.
% s(t) = Ryan's shape if supplied, else a smooth half-cosine rise over t_in
% and fall over t_out.
% dP_pl (the size of the swing) is CALCULATED by the caller so VT = tidal_volume.
if isempty(P_pl_shape)
    tc = mod(t, t_in + t_out);
    if tc <= t_in
        s = (1 - cos(pi * tc / t_in)) / 2;
    else
        s = (1 + cos(pi * (tc - t_in) / t_out)) / 2;
    end
else
    tp = mod(t, P_pl_shape(end, 1));
    s  = interp1(P_pl_shape(:, 1), P_pl_shape(:, 2), tp, 'linear');
end
P = P_pl_FRC + dP_pl * s;
end


function [t_span, Q, dQdt, V_A, P_alv, P_pl] = coupled_breathing(t_in, t_out, n_time, ...
    n_breaths, p_atm, P_pl_FRC, dP_pl, P_pl_shape, C_L, V_FRC, ...
    L_aw, dP_tree_fn, dP_extra_fn)
% Two coupled ODEs, solved together with ode15s (stiff: L/R ~ ms vs 4 s breath)
%   dV_A/dt = Q                                         (mass conservation)
%   dQ/dt   = (p_atm - P_alv - dP_extra(Q) - dP_tree(Q)) / L_aw
%                                                       (momentum, Newton II)
%   P_alv   = p_atm + P_pl(t) + P_tp_FRC + (V_A - V_FRC)/C_L  (lung elastance)
% dP_tree(Q) = my Gens 0-4 + Anna's Gens 5-16; dP_extra(Q) = nose-larynx.
P_tp_FRC = -P_pl_FRC;          % transpulmonary pressure holding the lung at FRC
t_cycle  = t_in + t_out;
P_alv_fn = @(t, V) p_atm + pleural_pressure(t, t_in, t_out, P_pl_FRC, dP_pl, P_pl_shape) ...
                   + P_tp_FRC + (V - V_FRC) / C_L;
rhs = @(t, y) [y(2); ...
    (p_atm - P_alv_fn(t, y(1)) - dP_extra_fn(y(2)) - dP_tree_fn(y(2))) / L_aw];

t_all = linspace(0, n_breaths * t_cycle, n_breaths * (n_time - 1) + 1)';
opts  = odeset('RelTol', 1e-8, 'AbsTol', [1e-12, 1e-12]);
[t_all, Y] = ode15s(rhs, t_all, [V_FRC; 0], opts);

last   = numel(t_all) - n_time + 1 : numel(t_all);      % final (periodic) breath
t_span = t_all(last) - t_all(last(1));
V_A    = Y(last, 1);
Q      = Y(last, 2);
P_alv  = zeros(n_time, 1);  P_pl = zeros(n_time, 1);  dQdt = zeros(n_time, 1);
for j = 1:n_time
    tj      = t_all(last(j));
    P_pl(j) = pleural_pressure(tj, t_in, t_out, P_pl_FRC, dP_pl, P_pl_shape);
    P_alv(j)= P_alv_fn(tj, V_A(j));
    dydt    = rhs(tj, Y(last(j), :)');
    dQdt(j) = dydt(2);
end

% Flow lags the muscle drive (time constant R*C), so shift the periodic
% breath to start where Q crosses zero upward: t = 0 = start of inspiration.
u      = 1:n_time-1;                                  % unique points (last = first)
start  = find(Q(u) < 0 & Q([2:n_time-1, 1]) >= 0, 1) + 1;
if isempty(start) || start > n_time-1, start = 1; end
order  = [start:n_time-1, 1:start-1, start];          % rotate, re-close the cycle
Q = Q(order); dQdt = dQdt(order); V_A = V_A(order);
P_alv = P_alv(order); P_pl = P_pl(order);
end


function [K1, R_total_ref, R_tree_ref, Q_peak_ref] = calibrate_extrathoracic( ...
    dP_alv_ref, VT_ref, T_insp_ref, dP_tree_fn)
% Extrathoracic laminar coefficient K1 from Guyton's normal-breath numbers.
% 1) Peak flow of a half-sine inspiration that moves VT_ref in T_insp_ref:
%       VT = integral_0^T Qpk sin(pi t/T) dt = 2 Qpk T / pi  ->  Qpk = pi VT / (2T)
% 2) Alveolar pressure is most negative when flow peaks, so the whole airway's
%    resistance at that instant is (Ohm's-law analogue, Sys Phys Eqn 6.2.3)
%       R_total = |P_alv| / Qpk
% 3) Resistances in series add (Sys Phys Eqn 6.2.10), so the part not
%    explained by Gens 0-16 is assigned to the nose/mouth/pharynx/larynx:
%       K1 = R_total - R_tree(Qpk)
Q_peak_ref  = pi * VT_ref / (2 * T_insp_ref);
R_total_ref = dP_alv_ref / Q_peak_ref;
R_tree_ref  = dP_tree_fn(Q_peak_ref) / Q_peak_ref;   % mine (0-4) + Anna's (5-16)
K1    = R_total_ref - R_tree_ref;
if K1 < 0
    warning('Tree resistance already exceeds the Guyton total; K1 set to 0');
    K1 = 0;
end
end


function C_deep_in = load_anna_exhale(anna_file, t_span, c_alv)
% Gas entering my Gen-4 exit during expiration (Anna's Gen-5 output).
C_deep_in = repmat(c_alv, numel(t_span), 1);
if isfile(anna_file)
    S = load(anna_file);
    if isfield(S, 'C_exh')
        C_deep_in = S.C_exh;
        fprintf('Expiratory gas loaded from %s\n', anna_file);
    end
end
end


function [V_D_total, V_D_intra, V_D_up, V_D_anna, my_fraction] = split_dead_space( ...
    tidal_volume, dead_space_fraction, extrathoracic_vol, vol_gen0_4, vol_conducting)
% VD = fraction*VT; remove the extrathoracic part; split the rest by Weibel volume.
V_D_total   = dead_space_fraction * tidal_volume;
V_D_intra   = V_D_total - extrathoracic_vol;
my_fraction = vol_gen0_4 / vol_conducting;
V_D_up      = V_D_intra * my_fraction;
V_D_anna    = V_D_intra - V_D_up;
end


function [p_node, table_data, peak_idx] = airway_mechanics(t_span, Q, dQdt, omega, ...
    k_vec, n_k, area_k, l_k, p_atm, p_trach, compliance_factor, rho_air, mu_air, use_pedley)
% Series of generations; n_k identical tubes in parallel within each.
% dP = R*Q + L*dQ/dt  (R: Womersley/Pedley/Poiseuille, L: Womersley inertance)
% Node 1 = trachea entry (p_trach); compliance is measured relative to p_atm.
num_t    = numel(t_span);
num_gens = numel(k_vec);
p_node   = zeros(num_t, num_gens + 1);
p_node(:, 1) = p_trach;
[~, peak_idx] = max(Q);
table_data = zeros(num_gens, 9);

for t_idx = 1:num_t
    for k_idx = 1:num_gens
        A     = area_k(k_idx) * (1 + compliance_factor * (p_node(t_idx, k_idx) - p_atm));
        r     = sqrt(A / (n_k(k_idx) * pi));
        d     = 2 * r;
        L_len = l_k(k_idx);

        Wo     = r * sqrt(rho_air * omega / mu_air);
        R_pois = 8 * mu_air * L_len / (pi * r^4);
        Lam    = Wo * 1i^(3/2);
        F10    = 2 * besselj(1, Lam) / (Lam * besselj(0, Lam));
        Z      = 1i * omega * rho_air * L_len / (pi * r^2) / (1 - F10);
        R_wom  = real(Z);
        L_tube = imag(Z) / omega;

        u_mean = abs(Q(t_idx)) / A;
        Re     = rho_air * u_mean * d / mu_air;
        Z_ped  = 0.327 * sqrt(Re * d / L_len);
        if use_pedley
            R_tube = R_pois * max([R_wom / R_pois, Z_ped, 1]);
        else
            R_tube = R_wom;
        end

        res_k   = R_tube / n_k(k_idx);
        inert_k = L_tube / n_k(k_idx);
        p_node(t_idx, k_idx+1) = p_node(t_idx, k_idx) - (res_k*Q(t_idx) + inert_k*dQdt(t_idx));

        if t_idx == peak_idx
            table_data(k_idx, :) = [k_vec(k_idx), n_k(k_idx), d*100, L_len*100, ...
                A*1e4, u_mean*100, Re, Wo, R_tube/R_pois];
        end
    end
end
end


function print_mechanics_table(table_data, Q_peak, p_peak, mmHg)
fprintf('Peak inspiratory flow = %.0f mL/s\n', Q_peak*1e6);
fprintf('%-6s%-6s%-10s%-10s%-12s%-16s%-9s%-8s%-8s\n', ...
    'gen_k', 'n_k', 'd_k(cm)', 'l_k(cm)', 'area(cm2)', 'velocity(cm/s)', 'Re', 'Wo', 'R/Rpois');
fprintf('%s\n', repmat('-', 1, 85));
for k_idx = 1:size(table_data, 1)
    fprintf('%-6d%-6d%-10.2f%-10.2f%-12.2f%-16.1f%-9.0f%-8.2f%-8.2f\n', table_data(k_idx, :));
end
fprintf('Pressure drop Gen 0 entry -> Gen 4 exit at peak flow: %.3f mmHg\n\n', ...
    (p_peak(1) - p_peak(end)) / mmHg);
end


function [c_gen4, c_trach] = deadspace_transport(t_span, Q, V_up, n_seg, n_breaths, ...
    c_inlet, C_deep_in, c_init)
% Tanks-in-series mass balance, one ODE per segment and species:
%   inspiration: V_seg dC_i/dt = Q   (C_{i-1} - C_i),  C_0     = c_inlet
%   expiration:  V_seg dC_i/dt = |Q| (C_{i+1} - C_i),  C_{n+1} = C_deep_in(t)
% Solved with ode45, repeated for n_breaths to reach periodic steady state.
V_seg = V_up / n_seg;
n_sp  = size(c_init, 2);
y0    = c_init(:);
opts  = odeset('RelTol', 1e-6, 'AbsTol', 1e-9, 'MaxStep', min(diff(t_span)));
rhs   = @(t, y) segment_rhs(t, y, t_span, Q, V_seg, n_seg, n_sp, c_inlet, C_deep_in);

for b = 1:n_breaths
    [~, Y] = ode45(rhs, t_span, y0, opts);
    y0 = Y(end, :)';
end

c_trach = zeros(numel(t_span), n_sp);
c_gen4  = zeros(numel(t_span), n_sp);
for t_idx = 1:numel(t_span)
    C = reshape(Y(t_idx, :), n_seg, n_sp);
    c_trach(t_idx, :) = C(1, :);
    if Q(t_idx) >= 0
        c_gen4(t_idx, :) = C(end, :);            % gas delivered to Anna
    else
        c_gen4(t_idx, :) = C_deep_in(t_idx, :);  % gas arriving from Anna
    end
end
end


function dydt = segment_rhs(t, y, t_span, Q, V_seg, n_seg, n_sp, c_inlet, C_deep_in)
q = interp1(t_span, Q, t, 'linear', 'extrap');
C = reshape(y, n_seg, n_sp);
if q >= 0
    upstream = [c_inlet; C(1:end-1, :)];
else
    c_deep   = interp1(t_span, C_deep_in, t, 'linear', 'extrap');
    upstream = [C(2:end, :); c_deep];
end
dCdt = abs(q) / V_seg * (upstream - C);
dydt = dCdt(:);
end


function check_ideal_gas(C_in, p_exit_Pa, p_atm, r_gas, t_body)
% PV = nRT  ->  total concentration must equal P/(RT).
c_total = sum(C_in, 2);
err_ref   = max(abs(c_total - p_atm/(r_gas*t_body)));
err_local = max(abs(c_total - p_exit_Pa/(r_gas*t_body)));
fprintf('PV=nRT check, sum(C_in) vs P/(RT): %.2e mol/m^3 at P_atm, %.2e at local Gen-4 P\n', ...
    err_ref, err_local);
end


function weibel_matrix = build_weibel_matrix(weibel_d_cm, weibel_l_cm, first_gen, last_gen)
% Gens first_gen..last_gen for Anna: [gen, n, d (cm), l (cm), area (cm^2), vol (cm^3)]
g    = (first_gen:last_gen)';
n    = 2.^g;
d    = weibel_d_cm(g + 1)';
l    = weibel_l_cm(g + 1)';
area = n .* pi .* (d/2).^2;
weibel_matrix = [g, n, d, l, area, area .* l];
end


function plot_dashboard(t_span, Q, p_node, p_atm, mmHg, pp_in, pco2_trach, table_data, VT, t_in)
% Phase switch = where flow actually turns outward (falls back to t_in).
i_sw = find(Q(2:end) < 0, 1) + 1;
if isempty(i_sw), t_switch = t_in; else, t_switch = t_span(i_sw); end
orange  = [0.93 0.49 0.07];   % reference lines (zero flow, Wo = 1, phase switch)
teal    = [0.00 0.62 0.62];   % PCO2 at trachea entry
figure('Name', 'Upper Airway (Gens 0-4) Dynamics Dashboard', 'Position', [100, 100, 1000, 800]);

subplot(2, 2, 1);
plot(t_span, Q*1e6, 'b-', 'LineWidth', 1.8);
yline(0, '--', 'Color', orange, 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Flow Q (mL/s)');
title(sprintf('Tracheal Airflow (V_T = %.0f mL)', VT*1e6)); grid on;

subplot(2, 2, 2);
plot(t_span, (p_atm - p_node(:, 1))/mmHg,   '-', 'Color', teal, 'LineWidth', 1.8); hold on;
plot(t_span, (p_atm - p_node(:, 3))/mmHg,   'm-',  'LineWidth', 1.8);
plot(t_span, (p_atm - p_node(:, end))/mmHg, 'r--', 'LineWidth', 1.8);
xlabel('Time (s)'); ylabel('P_{atm} - P (mmHg)');
legend('Trachea entry (after nose-larynx)', 'Gen 2 entry', 'Gen 4 exit (handoff)', 'Location', 'best');
title('Pressure Drop: Nose-Larynx and Gens 0-4'); grid on;

subplot(2, 2, 3);
plot(t_span, pp_in.o2,  'g-',  'LineWidth', 1.8); hold on;
plot(t_span, pp_in.co2, 'm-',  'LineWidth', 1.8);
plot(t_span, pco2_trach, '--', 'Color', teal, 'LineWidth', 1.8);
xline(t_switch, ':', 'insp | exp', 'Color', orange, 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Partial pressure (mmHg)');
legend('P_{O2} at Gen 4', 'P_{CO2} at Gen 4', 'P_{CO2} at trachea entry', 'Location', 'east');
title('Dead-Space Washout at the Handoff Boundary'); grid on;

subplot(2, 2, 4);
yyaxis left;
b1 = bar(table_data(:, 1), table_data(:, 8), 'FaceColor', [0.8 0.3 0.3], 'FaceAlpha', 0.6);
ylabel('Womersley Number (Wo)');
y1 = yline(1.0, '--', 'Wo = 1', 'Color', orange, 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
set(get(get(y1, 'Annotation'), 'LegendInformation'), 'IconDisplayStyle', 'off');
yyaxis right;
p1 = plot(table_data(:, 1), table_data(:, 7), 'b-o', 'LineWidth', 2);
ylabel('Reynolds Number (Re) at peak flow');
legend([b1, p1], {'Womersley No.', 'Reynolds No.'}, 'Location', 'northeast');
xlabel('Generation (Weibel k)');
title('Flow Regime by Generation'); grid on;
end


function plot_coupling(t_span, Q, V_A, V_FRC, P_alv, P_pl, p_atm, mmHg)
% Same layout as Guyton Fig. 37-2: volume, alveolar and pleural pressure.
orange = [0.93 0.49 0.07];
figure('Name', 'Airway-Alveolar Coupling', 'Position', [150, 150, 800, 800]);

subplot(3, 1, 1);
plot(t_span, (V_A - V_FRC)*1e6, 'b-', 'LineWidth', 1.8);
ylabel('V_A - FRC (mL)'); title('Lung Volume Change'); grid on;

subplot(3, 1, 2);
plot(t_span, (P_alv - p_atm)/mmHg, 'r-', 'LineWidth', 1.8); hold on;
yline(0, '--', 'Color', orange, 'LineWidth', 1.5);
ylabel('P_{alv} - P_{atm} (mmHg)'); title('Alveolar Pressure (drives Q)'); grid on;

subplot(3, 1, 3);
plot(t_span, P_pl/mmHg, 'm-', 'LineWidth', 1.8); hold on;
yyaxis right; plot(t_span, Q*1e6, 'g-', 'LineWidth', 1.4); ylabel('Q (mL/s)');
yyaxis left; ylabel('P_{pl} (mmHg gauge)');
xlabel('Time (s)'); title('Pleural Pressure (muscle drive) and Resulting Flow'); grid on;
end
