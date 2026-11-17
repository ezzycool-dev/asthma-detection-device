function out = airway_model(lung, p)
% AIRWAY_MODEL  Conducting airway, Weibel Gens 0-16, in one file.
%   J: Gens 0-4 (trachea to segmental bronchi). Anna: Gens 5-16 (to the
%   terminal bronchioles). This file has no stand-ins: the lung mechanics and
%   the alveolar gas come from the other subteams' code through the struct LUNG.
%
% USE
%   p   = airway_model('params');    every constant, each with its source;
%                                    edit fields, then pass p back in
%   out = airway_model(lung);        solve one periodic breath (VT fixed at 500 mL)
%   out = airway_model(lung, p);     same, with edited constants
%   airway_model('summary', out);    print the main results
%   airway_model('plot', out);       6-panel dashboard
%
% LUNG = what the other subteams supply (units are checked on entry)
%   From the mechanics model (required)
%     V_FRC     [L]           functional residual capacity
%     P_pl_FRC  [mmHg gauge]  pleural pressure at FRC (start of inspiration)
%     P_alv_fn  @(t, V_A, P_pl) -> alveolar pressure [mmHg ABSOLUTE];
%               t [s], V_A lung volume [L], P_pl pleural pressure [mmHg gauge]
%     shape     [t (s), 0-1]  optional shape of the muscle drive over one breath;
%               [] or missing = half-cosine rise over t_in, fall over t_out.
%               Only its shape is used: the size of the pleural swing is
%               calculated so VT = 500 mL (team agreement).
%   From the alveolar / gas-exchange model (optional)
%     C_alv_fn  @(t) -> 1 x 4 alveolar gas [mol/m^3], columns O2 CO2 N2 H2O:
%               the gas breathed back out on expiration. Without it the model
%               solves flow and pressures only (out.has_gas = false). Flow does
%               not depend on gas, so a first pass without it gives the same flow.
%   source      optional text label for the summary
%
% OUT (team units: pressure mmHg, flow L/s with + = inspiration, volume L,
%      time s, gas mol/m^3 with columns O2 CO2 N2 H2O)
%   time, Q_V, dQ_V_dt, VT, alv_gas_volume     one breath, t = 0 at start of inspiration
%   P_alv_mmHg (absolute), P_pl_mmHg (gauge, calculated), dP_pl (calculated swing)
%   p_trach_mmHg, P_upper_mmHg (Gens 0-4 nodes), P_lower_mmHg (Gens 5-16 nodes)
%   V_D_model    dead space the model uses (0.3 x VT = 150 mL)
%   C_inspired   fresh humidified tracheal gas, 1 x 4 (the inspired gas)
%   C_trach, C_gen4, C_gen16   gas crossing the trachea entry, Gen 4/5 and the
%                Gen-16 exit, N x 4 (empty when has_gas is false)
%   lower_view   Anna's results under her original field names and units
% For a gas-exchange model: alveolar ventilation = (out.VT - out.V_D_model) / T;
% inspired gas = out.C_inspired (out.C_trach(1,:) is end-expired gas, not inspired).
%
% Sources: Guyton & Hall; Systems Physiology (Sys Phys); Weibel model A as
% tabulated in Murayama et al., J Drug Deliv 2019, Table 1; Pedley, Schroter &
% Sudlow 1971. Each constant names its source in default_params below.

%% Commands
if nargin < 1
    error('airway_model:input', 'airway_model needs the lung struct. Type  help airway_model');
end
if ischar(lung) || isa(lung, 'string')
    cmd = lower(char(lung));
    out = [];
    switch cmd
        case 'params'
            out = default_params();
        case {'summary', 'plot'}
            if nargin < 2
                error('airway_model:input', 'Use  airway_model(''%s'', out)', cmd);
            end
            if strcmp(cmd, 'summary')
                print_summary(p);           % here the second input is out
            else
                plot_dashboard(p);          % here the second input is out
            end
        otherwise
            error('airway_model:command', ...
                'Unknown command ''%s''. Use ''params'', ''summary'' or ''plot''.', cmd);
    end
    return
end

%% Solve
if nargin < 2 || isempty(p)
    p = default_params();
end
lung = check_lung(lung, p);
out  = solve_airway(p, lung);
end


%% =====================================================================
%% CONSTANTS
%% =====================================================================

function p = default_params()
% Every constant in the airway model. One value per line, unit and source in
% the comment. Units used across ALL team-facing values:
%   pressure  mmHg  (absolute unless the name says gauge)
%   flow      L/s   (Q_V; + = inspiration)
%   volume    L
%   time      s
%   gas       mol/m^3 (= mmol/L), columns O2 CO2 N2 H2O
% SI (Pa, m^3) appears only inside the physics helpers, because mu_air and
% r_gas are SI.

%% Unit conversions
p.mmHg  = 133.322;              % Pa per mmHg
p.cmH2O = 98.0665;              % Pa per cmH2O
p.cm2mm = p.cmH2O / p.mmHg;     % mmHg per cmH2O (0.7356); Guyton quotes lung pressures in cmH2O

%% Atmosphere and gas
p.p_atm      = 760;             % mmHg  sea-level barometric pressure (Guyton Tbl 39-1)
p.p_h2o_body = 47;              % mmHg  water vapour pressure at 37 C (Guyton Ch. 39)
p.f_io2      = 0.21;            % -     inspired O2 fraction, dry air (Guyton Tbl 39-1: 20.84%)
p.rho_air    = 1.13;            % kg/m^3 (= g/L) air density at 37 C (Sys Phys Ch. 6.2)
p.mu_air     = 19.1e-6;         % Pa s  air viscosity at 37 C (Sys Phys Ch. 6.2)
p.r_gas      = 8.314;           % J/(mol K) ideal gas constant
p.t_body     = 310.15;          % K     37 C
p.species    = {'o2', 'co2', 'n2', 'h2o'};
p.pph_o2  = 149.4;              % mmHg  humidified tracheal air (Sys Phys Tbl 6.3.2)
p.pph_co2 = 0.2;                % mmHg  (Sys Phys Tbl 6.3.2)
p.pph_n2  = 563.3;              % mmHg  N2 + inert gases (Sys Phys Tbl 6.3.2)
p.pph_h20 = 47;                 % mmHg  (Sys Phys Tbl 6.3.2)
p.c_trach = [p.pph_o2 p.pph_co2 p.pph_n2 p.pph_h20] * p.mmHg / (p.r_gas * p.t_body);  % mol/m^3

%% Breathing (team agreements)
p.t_cycle      = 4;             % s     one breath, team agreement (15 breaths/min)
p.t_in         = 2;             % s     inspiration (Guyton Ch. 37: "the 2 seconds")
p.t_out        = p.t_cycle - p.t_in;   % s
p.n_time       = 100;           % points per breath on the shared time grid
p.n_breaths    = 3;             % breaths simulated to reach periodic steady state
p.tidal_volume = 0.500;         % L     team agreement (Guyton Ch. 37); FIXED
p.VT_tol       = 1e-4;          % L     tolerance on the solved VT (0.1 mL)

%% Dead space
p.dead_space_fraction = 0.3;    % -     VD = 0.3*VT = 150 mL (Guyton Ch. 37: ~150 mL)
p.measured_dead_space_vol = p.dead_space_fraction * p.tidal_volume;   % L
p.V_extra    = 0.072;           % L     nose/mouth/pharynx/larynx part, not modelled as gas (Brewer & Orr)
p.n_seg_upper = 30;             % segments in Gens 0-4; Gens 5-16 use the same segment volume

%% Airway geometry, Gens 0-23: Weibel human model A as tabulated in
% Murayama et al., J Drug Deliv 2019, Table 1 (doi:10.1155/2019/3921426);
% every diameter and length below matches that table.
p.weibel_d_cm = [1.80 1.22 0.83 0.56 0.45 0.35 0.28 0.23 0.186 0.154 0.130 0.109 ...
                 0.095 0.082 0.074 0.066 0.060 0.054 0.050 0.047 0.045 0.043 0.041 0.041];
p.weibel_l_cm = [12.0 4.76 1.90 0.76 1.27 1.07 0.90 0.76 0.64 0.54 0.46 0.39 ...
                 0.33 0.27 0.23 0.20 0.165 0.141 0.117 0.099 0.083 0.076 0.059 0.050];
                 % gen 21 length 0.076 cm per the paper (was 0.070)
p.gens_upper = 0:4;             % J
p.gens_lower = 5:16;            % Anna (conducting zone ends at Gen 16, Sys Phys Ch. 6.1)

%% Resistance
p.use_pedley = true;            % Pedley entrance-flow correction (Pedley, Schroter & Sudlow 1971)
p.use_extrathoracic_R = true;   % nose-to-larynx resistance, Rohrer form (Sys Phys Eqn 6.2.10)
p.dP_alv_ref = 1.0 * p.cm2mm;   % mmHg  |alveolar P| at peak normal inspiration (Guyton Ch. 37: ~1 cmH2O)
p.VT_ref     = 0.5;             % L     volume moved by that pressure (Guyton Ch. 37)
p.T_insp_ref = 2;               % s     in this time (Guyton Ch. 37)
p.K2         = 0;               % mmHg/(L/s)^2 turbulent term; Re < 2000 at rest (Sys Phys Ch. 6.2)
                                % K1 is calibrated at run time (calibrate_extrathoracic)

%% Anna's section (Gens 5-16) - her values and her switches
% Her Weibel table, AS PUBLISHED (values unchanged): Murayama N, Asai K, Murayama K,
% Doi S, Kameda M. Dry powder and budesonide inhalation suspension deposition rates
% in asthmatic airway-obstruction regions. J Drug Deliv 2019; 3921426,
% doi:10.1155/2019/3921426, Table 1 (Weibel human model A, from the Annals of the ICRP).
% [Gen, BranchCount, Diameter_cm, Length_cm, CrossSection_cm2, Vol_cm3]
p.anna_weibel_matrix = [
     5,    32,    0.350, 1.070,   3.11,   3.30;
     6,    64,    0.280, 0.900,   3.96,   3.53;
     7,   128,    0.230, 0.760,   4.10,   3.85;
     8,   256,    0.186, 0.640,   6.95,   4.45;
     9,   512,    0.154, 0.540,   9.65,   5.17;
    10,  1024,    0.130, 0.460,  13.40,   6.31;
    11,  2048,    0.109, 0.390,  19.60,   7.56;
    12,  4096,    0.095, 0.330,  28.80,   9.82;
    13,  8192,    0.082, 0.270,  44.50,  12.45;
    14, 16384,    0.074, 0.230,  69.40,  16.40;
    15, 32768,    0.066, 0.200, 113.00,  21.70;
    16, 65536,    0.060, 0.165, 180.00,  29.70];
p.lower_pressure_mode = 'computed';     % 'computed'     = from her Poiseuille resistance,
                                        %                  starting at J's Gen-4 exit (default)
                                        % 'anna_formula' = her original P_atm + 0.8 sin(2 pi t/T)
p.anna_P_amp = 0.8;                     % mmHg  amplitude in her original formula (no source given)
p.lower_mixing = 'chain';               % 'chain' = 74 segments of 0.75 mL (default)
                                        % 'single_tank' = her one well-mixed compartment
p.lower_volume_source = 'dead_space_share';  % TEAM DECISION (Oct 11): total dead space
                                        %   stays 0.3*VT = 150 mL (Guyton), so Anna's
                                        %   section holds her share, 55.5 mL.
                                        % 'weibel_table' = her table volume, 124.24 mL,
                                        %   unscaled; total dead space would be 218.8 mL
                                        %   (44% of VT). Kept only for comparison.
p.lower_include_inertance = false;      % her model has no gas inertia in Gens 5-16

% Airway-wall compliance of Gens 5-16 (subteam formula, Oct 14; replaces the
% hard-coded 1.5). Only feeds Anna's reported volume, out.lower_view.volume.
p.anna_V_baseline_mL = sum(p.anna_weibel_matrix(:, 6));   % mL  124.24, her table
p.anna_C_ref         = 75.0;    % mL/mmHg  CITATION NEEDED
p.anna_V_ref_mL      = 6000;    % mL       CITATION NEEDED
p.anna_airway_compliance = p.anna_C_ref * p.anna_V_baseline_mL / p.anna_V_ref_mL;   % 1.553 mL/mmHg

%% Bookkeeping
p.version = 'airway-v0.4 one-file (J + Anna, Gens 0-16, no stand-ins)';
end


%% =====================================================================
%% INPUT CHECK AND SOLVER
%% =====================================================================

function lung = check_lung(lung, p)
% Checks the inputs from the other subteams before solving: required fields,
% optional fields and units (evaluated at rest: t = 0, V_A = FRC).
if ~isstruct(lung)
    error('airway_model:lung', 'The first input must be the lung struct. Type  help airway_model');
end
need = {'V_FRC', 'P_pl_FRC', 'P_alv_fn'};
miss = need(~isfield(lung, need));
if ~isempty(miss)
    error('airway_model:lung', ...
        'lung is missing %s (from the mechanics model). Type  help airway_model', strjoin(miss, ', '));
end
if ~isfield(lung, 'shape'),    lung.shape    = [];                    end
if ~isfield(lung, 'C_alv_fn'), lung.C_alv_fn = [];                    end
if ~isfield(lung, 'source'),   lung.source   = 'unnamed lung model';  end
if lung.V_FRC < 0.5 || lung.V_FRC > 10
    error('airway_model:units', ...
        'lung.V_FRC = %g. It must be in L (Guyton FRC is about 2.3 L).', lung.V_FRC);
end
if lung.P_pl_FRC >= 0 || lung.P_pl_FRC < -20
    error('airway_model:units', ['lung.P_pl_FRC = %g. It must be gauge pressure in mmHg, ' ...
        'below zero (Guyton: -5 cmH2O = -3.68 mmHg).'], lung.P_pl_FRC);
end
P0 = lung.P_alv_fn(0, lung.V_FRC, lung.P_pl_FRC);
if ~isscalar(P0) || abs(P0 - p.p_atm) > 50
    error('airway_model:units', ['lung.P_alv_fn must return ABSOLUTE alveolar pressure in mmHg ' ...
        '(about %g at rest). At t = 0, V_A = V_FRC, P_pl = P_pl_FRC it returned %s.'], ...
        p.p_atm, mat2str(P0, 4));
end
if ~isempty(lung.shape) && size(lung.shape, 2) ~= 2
    error('airway_model:lung', 'lung.shape must be [] or two columns: [time (s), drive 0-1].');
end
if ~isempty(lung.C_alv_fn)
    c0    = lung.C_alv_fn(0);
    c_tot = p.p_atm * p.mmHg / (p.r_gas * p.t_body);       % 39.3 mol/m^3 at 760 mmHg, 37 C
    if ~isequal(size(c0), [1 4]) || abs(sum(c0) - c_tot) > 0.1 * c_tot
        error('airway_model:units', ['lung.C_alv_fn(t) must return a 1 x 4 row [O2 CO2 N2 H2O] ' ...
            'in mol/m^3 summing to about %.1f. It returned %s. Partial pressures in mmHg ' ...
            'convert with  P_mmHg * p.mmHg / (p.r_gas * p.t_body).'], c_tot, mat2str(c0, 4));
    end
end
end


function out = solve_airway(p, lung)
% Solve order: 1 geometry  2 tree resistance  3 nose-to-larynx K1
%   4 coupled flow (VT fixed)  5 pressures top-down  6 one gas chain trachea -> Gen 16
%   7 package outputs

%% 1-2. Geometry and airway-tree resistance
gu = upper_geometry(p);
gl = lower_geometry(p);
dP_tree_fn = @(Q) upper_dP(Q, p, gu) + lower_dP(Q, p, gl);     % mmHg

%% 3. Nose-to-larynx resistance (Rohrer form, K1 calibrated from Guyton)
if p.use_extrathoracic_R
    [K1, cal] = calibrate_extrathoracic(p, dP_tree_fn);
else
    K1 = 0;  cal = struct();
end
K2 = p.K2;
dP_extra_fn = @(Q) K1 * Q + K2 * Q .* abs(Q);                  % mmHg

%% 4. One flow for everyone (VT fixed, pleural swing calculated)
flow = coupled_breathing(p, lung, gu.L + gl.L, dP_tree_fn, dP_extra_fn);
time = flow.time;

%% 5. Pressures top-down
P_trach = p.p_atm - dP_extra_fn(flow.Q_V);
P_upper = upper_profile(time, flow.Q_V, flow.dQ_V_dt, P_trach,         p, gu);
P_lower = lower_profile(time, flow.Q_V, flow.dQ_V_dt, P_upper(:, end), p, gl);

%% 6. Dead space split and one gas chain
V_intra  = p.measured_dead_space_vol - p.V_extra;              % L, from 0.3*VT
frac_up  = sum(gu.vol) / (sum(gu.vol) + sum(gl.vol));          % Weibel volume fraction
V_D_up   = V_intra * frac_up;                                  % L, J: share of 0.3*VT
switch p.lower_volume_source
    case 'weibel_table'       % Anna: her table volume, unscaled (124.24 mL)
        V_D_anna = sum(gl.vol) * 1e3;                          % m^3 -> L
    case 'dead_space_share'   % Anna: her share of 0.3*VT (55.5 mL)
        V_D_anna = V_intra - V_D_up;
    otherwise
        error('p.lower_volume_source must be ''weibel_table'' or ''dead_space_share''');
end
V_D_model = p.V_extra + V_D_up + V_D_anna;                     % L, dead space the model uses
V_seg    = V_D_up / p.n_seg_upper;
switch p.lower_mixing
    case 'chain'          % same segment volume as Gens 0-4
        n_low = max(1, round(V_D_anna / V_seg));
    case 'single_tank'    % Anna's original: one well-mixed compartment
        n_low = 1;
    otherwise
        error('p.lower_mixing must be ''chain'' or ''single_tank''');
end
V_segs   = [repmat(V_seg, p.n_seg_upper, 1); repmat(V_D_anna / n_low, n_low, 1)];

has_gas = ~isempty(lung.C_alv_fn);
if has_gas
    c_init = repmat(lung.C_alv_fn(0), numel(V_segs), 1);
    gas = segment_transport(time, flow.Q_V, V_segs, p.c_trach, lung.C_alv_fn, ...
                            p.n_breaths, c_init);
    % Gas crossing each boundary (inspiration: what leaves the segment above it;
    % expiration: what leaves the segment below it / comes from the alveoli)
    i4  = p.n_seg_upper;            % last segment of Gens 0-4
    ins = flow.Q_V >= 0;
    C_seg = @(j) squeeze(gas.C(:, j, :));
    C_gen4 = C_seg(i4);   C_below = C_seg(i4 + 1);   C_gen4(~ins, :) = C_below(~ins, :);
    C_gen16 = C_seg(numel(V_segs));
    for j = find(~ins)'
        C_gen16(j, :) = lung.C_alv_fn(time(j));
    end
end

%% 7. Package (team units: mmHg, L/s, L, mol/m^3)
out.time          = time;                 % s
out.Q_V           = flow.Q_V;             % L/s
out.dQ_V_dt       = flow.dQ_V_dt;         % L/s^2
out.VT            = flow.VT;              % L
out.alv_gas_volume = flow.V_A;            % L
out.P_alv_mmHg    = flow.P_alv;           % mmHg absolute
out.P_pl_mmHg     = flow.P_pl;            % mmHg gauge (calculated)
out.dP_pl         = flow.dP_pl;           % mmHg, calculated pleural swing
out.p_trach_mmHg  = P_trach;              % mmHg absolute, trachea entry
out.P_upper_mmHg  = P_upper;              % N x 6,  Gen 0 entry ... Gen 4 exit
out.P_lower_mmHg  = P_lower;              % N x 13, Gen 5 entry ... Gen 16 exit
out.p_gen4_mmHg   = P_upper(:, end);      % handoff pressure J -> Anna
out.K1            = K1;                   % mmHg/(L/s)
out.K2            = K2;                   % mmHg/(L/s)^2
out.calibration   = cal;
out.measured_dead_space_vol = p.measured_dead_space_vol;   % L, agreed 0.3*VT (150 mL)
out.V_D_model     = V_D_model;            % L, dead space the model actually uses
out.V_extra       = p.V_extra;            % L, nose-larynx part (not tracked as gas)
out.V_D_up        = V_D_up;               % L
out.V_D_anna      = V_D_anna;             % L
out.V_segs        = V_segs;               % L
out.n_seg_upper   = p.n_seg_upper;
out.C_inspired    = p.c_trach;            % 1 x 4, fresh humidified tracheal gas (inspired)
out.has_gas       = has_gas;
if has_gas
    out.C_chain   = gas.C;                % N x n_seg x 4, mol/m^3
    out.C_trach   = C_seg(1);             % N x 4, gas at the trachea entry (capnogram)
    out.C_gen4    = C_gen4;               % N x 4, gas crossing Gen 4 / Gen 5
    out.C_gen16   = C_gen16;              % N x 4, gas crossing into the alveoli
    out.gas_periodic_err = max(abs(gas.y_end_last - gas.y_start_last));   % mol/m^3
else
    out.C_chain = [];  out.C_trach = [];  out.C_gen4 = [];  out.C_gen16 = [];
    out.gas_periodic_err = NaN;
end
out.flow_periodic_err = flow.periodic_err;                     % L
out.geometry      = struct('upper', gu, 'lower', gl);
out.weibel_matrix = weibel_matrix(p, 5:23);
out.species       = p.species;
out.lung_source   = lung.source;
out.units = struct('time', 's', 'Q_V', 'L/s (+ = inspiration)', 'dQ_V_dt', 'L/s^2', ...
    'alv_gas_volume', 'L', 'pressures', 'mmHg (absolute unless named gauge)', ...
    'K1', 'mmHg/(L/s)', 'K2', 'mmHg/(L/s)^2', 'volumes', 'L', ...
    'gas', 'mol/m^3 (= mmol/L), columns o2 co2 n2 h2o');
out.meta = struct('version', p.version, 'created', datestr(now, 'yyyy-mm-dd HH:MM'), ...
                  'params', p);

%% Anna's outputs under her original field names and units
out.lower_view = lower_view(out, p, gl);
end


function M = weibel_matrix(p, gens)
% [gen, n, d (cm), l (cm), total area (cm^2), volume (cm^3)]
g = gens(:);  n = 2.^g;
d = p.weibel_d_cm(g + 1)';  l = p.weibel_l_cm(g + 1)';
a = n .* pi .* (d/2).^2;
M = [g, n, d, l, a, a .* l];
end


%% =====================================================================
%% J: GENS 0-4 (trachea to segmental bronchi)
%% =====================================================================

function g = upper_geometry(p)
% Gens 0-4 geometry and impedance (see weibel_geometry for fields).
g = weibel_geometry(p, p.gens_upper);
end


function dP = upper_dP(Q_V, p, g)
% Resistive pressure drop across Gens 0-4.
%   Q_V [L/s] scalar or vector (signed, + = inspiration)
%   dP  [mmHg], same size and sign as Q_V
% Law: Hagen-Poiseuille resistance scaled by max(Womersley, Pedley, 1);
% generations in series add, tubes within a generation are in parallel.
dP = reshape(sum(generation_drops(Q_V, p, g), 2), size(Q_V));
end


function P = upper_profile(time, Q_V, dQ_V_dt, P_top, p, g)
% Node pressures along Gens 0-4 over the breath.
%   time    [s]      N x 1
%   Q_V     [L/s]    N x 1
%   dQ_V_dt [L/s^2]  N x 1
%   P_top   [mmHg]   N x 1 absolute pressure at the trachea entry
%   P       [mmHg]   N x (5+1) absolute: column 1 = Gen 0 entry, end = Gen 4 exit
% Momentum balance per generation (Newton's 2nd law on the gas column):
%   P_k - P_{k+1} = R_k(Q) Q + L_k dQ/dt
drops = generation_drops(Q_V, p, g) + dQ_V_dt(:) * g.L_gen';
P = P_top(:) - [zeros(numel(time), 1), cumsum(drops, 2)];
end


%% =====================================================================
%% ANNA: GENS 5-16 (bronchi to terminal bronchioles)
%% =====================================================================

function g = lower_geometry(p)
% Gens 5-16, from Anna's simulate_bronchioles_gen5_16.m, lines 8-41.
% Geometry: her Weibel table as published (p.anna_weibel_matrix, values unchanged).
% Resistance: her law, Hagen-Poiseuille per generation with N branches in parallel
%   R_gen = 8 mu L / (pi r^4 N)      (Sys Phys Eqn 6.2.1)
% Inertance: none (her model has no gas inertia); p.lower_include_inertance = true
% adds the Womersley inertance used in Gens 0-4.
W = p.anna_weibel_matrix;
g.weibel_matrix = W;
g.k    = W(:, 1);
g.n    = W(:, 2);
g.d    = W(:, 3) / 100;            % m
g.l    = W(:, 4) / 100;            % m
g.area = W(:, 5) * 1e-4;           % m^2  (her table)
g.vol  = W(:, 6) * 1e-6;           % m^3  (her table)
g.V_baseline_mL = sum(W(:, 6));    % 124.24 mL, her line 34

r      = g.d / 2;
R_si   = 8 * p.mu_air * g.l ./ (pi * r.^4 .* g.n);   % Pa s/m^3, her line 40
g.R_gen   = R_si * 1e-3 / p.mmHg;                    % mmHg/(L/s) (= her mmHg s/mL x 1000)
g.R_total = sum(g.R_gen);

omega = 2*pi / p.t_cycle;
g.Wo  = r .* sqrt(p.rho_air * omega / p.mu_air);     % for the dashboard only
if p.lower_include_inertance
    [~, ~, L_par] = womersley_terms(g.d, g.l, g.n, p.rho_air, p.mu_air, omega);
    g.L_gen = L_par * 1e-3 / p.mmHg;                 % mmHg s^2/L
else
    g.L_gen = zeros(size(g.k));
end
g.L = sum(g.L_gen);
end


function dP = lower_dP(Q_V, p, g)
% Resistive pressure drop across Gens 5-16. Her law (lines 35-41): Poiseuille
% resistance, generations in series, branches in parallel; linear in flow.
%   Q_V [L/s] scalar or vector, signed (+ = inspiration)
%   dP  [mmHg], same size and sign as Q_V
dP = g.R_total * Q_V;
end


function P = lower_profile(time, Q_V, dQ_V_dt, P_top, p, g)
% Node pressures along Gens 5-16 over the breath.
%   P_top [mmHg] N x 1 = pressure at the Gen-4 exit (J's last node)
%   P     [mmHg] N x 13 absolute: column 1 = Gen 5 entry, end = Gen 16 exit
% Mode 'computed' (default): momentum balance per generation with her
%   Poiseuille resistance, P_k - P_{k+1} = R_k Q + L_k dQ/dt, starting at P_top.
% Mode 'anna_formula': her original line 44, P_airway = P_atm + 0.8 sin(2 pi t / T),
%   the same value at every node. It does not start from P_top or end at P_alv.
switch p.lower_pressure_mode
    case 'computed'
        drops = Q_V(:) * g.R_gen' + dQ_V_dt(:) * g.L_gen';
        P = P_top(:) - [zeros(numel(time), 1), cumsum(drops, 2)];
    case 'anna_formula'
        P_airway = p.p_atm + p.anna_P_amp * sin(2*pi * time(:) / p.t_cycle);
        P = repmat(P_airway, 1, numel(g.k) + 1);
    otherwise
        error('p.lower_pressure_mode must be ''computed'' or ''anna_formula''');
end
end


function v = lower_view(out, p, g)
% Anna's results under the field names and units of her original sim_results
% struct (simulate_bronchioles_gen5_16.m, lines 84-104), so her plots and report
% code keep working. Units as she used them: mL, mL/s, mmHg, cm/s.
to_mm = @(C) C * p.r_gas * p.t_body / p.mmHg;      % mol/m^3 -> mmHg
N     = numel(out.time);

v.time    = out.time;
v.airflow = out.Q_V * 1e3;                          % mL/s
% Her compartment pressure = mean of her node pressures (mmHg absolute)
v.pressure = mean(out.P_lower_mmHg, 2);
v.P_total  = v.pressure;
v.pressure_gen5_entry = out.P_lower_mmHg(:, 1);
v.pressure_gen16_exit = out.P_lower_mmHg(:, end);

% Her wall-compliance volume (her lines 46-47). Transmural pressure taken as
% airway minus pleural with BOTH in gauge mmHg.
P_trans  = (v.pressure - p.p_atm) - out.P_pl_mmHg;
v.volume = out.V_D_anna * 1e3 + p.anna_airway_compliance * (P_trans - mean(P_trans));   % mL

v.geometry.weibel_matrix = g.weibel_matrix;
v.geometry.V_baseline    = g.V_baseline_mL;          % 124.24 mL, her table
v.geometry.V_dead_space  = out.V_D_anna * 1e3;       % mL actually used
v.geometry.R_total       = g.R_total * 1e-3;          % mmHg s/mL, her unit
v.geometry.generation_velocities = (v.airflow' ./ g.weibel_matrix(:, 5));   % cm/s, her line 55

if out.has_gas
    % Gas: volume-weighted mean of her segments ("her compartment"), and the gas
    % leaving Gen 16 toward the alveoli
    iLow  = out.n_seg_upper + 1 : numel(out.V_segs);    % her segments in the gas chain
    w     = out.V_segs(iLow) / sum(out.V_segs(iLow));   % volume weights
    C_mean = zeros(N, 4);
    for s = 1:4
        C_mean(:, s) = out.C_chain(:, iLow, s) * w;
    end
    names = {'O2', 'CO2', 'N2', 'H2O'};
    for s = 1:4
        v.partial_pressures.(names{s})      = to_mm(C_mean(:, s));
        v.partial_pressures_exit.(names{s}) = to_mm(out.C_gen16(:, s));
    end
    Psum = to_mm(sum(C_mean, 2));
    v.gas_fractions.O2       = v.partial_pressures.O2  ./ Psum;
    v.gas_fractions.CO2      = v.partial_pressures.CO2 ./ Psum;
    v.gas_fractions.N2_inert = v.partial_pressures.N2  ./ Psum;
    v.gas_fractions.H2O      = v.partial_pressures.H2O ./ Psum;
    v.humidity.P_H2O_mmHg            = v.partial_pressures.H2O;
    v.humidity.relative_humidity_pct = 100 * v.partial_pressures.H2O / p.p_h2o_body;
end
v.temperature = (p.t_body - 273.15) * ones(N, 1);
v.modes = struct('pressure', p.lower_pressure_mode, 'mixing', p.lower_mixing, ...
                 'inertance', p.lower_include_inertance);
end


%% =====================================================================
%% SHARED PHYSICS (flow solver, nose-larynx calibration, gas chain)
%% =====================================================================

function [K1, cal] = calibrate_extrathoracic(p, dP_tree_fn)
% Nose-to-larynx laminar coefficient K1 [mmHg/(L/s)].
% From Guyton Ch. 37: ~1 cmH2O alveolar pressure "is enough to pull 0.5 liter
% of air into the lungs in the 2 seconds required for normal quiet inspiration".
% 1) Peak flow of a half-sine inspiration moving VT_ref in T_insp_ref:
%       Q_pk = pi * VT_ref / (2 * T_insp_ref)
% 2) Whole-airway resistance at peak flow (Ohm's-law analogue, Sys Phys 6.2.3):
%       R_total = dP_alv_ref / Q_pk
% 3) Resistances in series add (Rohrer, Sys Phys Eqn 6.2.10), so the part not
%    explained by Gens 0-16 belongs to the nose/mouth/pharynx/larynx:
%       K1 = R_total - R_tree(Q_pk)
cal.Q_pk    = pi * p.VT_ref / (2 * p.T_insp_ref);       % L/s
cal.R_total = p.dP_alv_ref / cal.Q_pk;                 % mmHg/(L/s)
cal.R_tree  = dP_tree_fn(cal.Q_pk) / cal.Q_pk;         % mmHg/(L/s)
K1 = cal.R_total - cal.R_tree;
if K1 < 0
    warning('Airway tree resistance exceeds the Guyton total; K1 set to 0.');
    K1 = 0;
end
cal.K1 = K1;
end


function flow = coupled_breathing(p, lung, L_total, dP_tree_fn, dP_extra_fn)
% Solve the airway-lung flow for one periodic breath.
% Units: V [L], Q_V [L/s], pressures [mmHg], L_total [mmHg s^2/L].
% Two ODEs solved together with ode15s (stiff: airway L/R ~ ms, breath 4 s):
%   dV_A/dt  = Q_V                                   conservation of mass
%   L dQ_V/dt = (P_atm - P_alv) - dP_extra(Q_V) - dP_tree(Q_V)
%                                                    momentum (Newton's 2nd law)
%   P_alv = lung.P_alv_fn(t, V_A, P_pl(t))           the mechanics subteam's lung
% VT is FIXED (team agreement): the size of the pleural swing dP_pl is the
% unknown, rescaled until the solved VT equals p.tidal_volume (2-3 passes).
dP_pl = -2.5 * p.cm2mm;          % mmHg, starting guess (Guyton: -5 -> -7.5 cmH2O)
for pass = 1:10
    [flow, VT] = solve_once(p, lung, L_total, dP_tree_fn, dP_extra_fn, dP_pl);
    if abs(VT - p.tidal_volume) < p.VT_tol, break; end
    dP_pl = dP_pl * p.tidal_volume / VT;
end
flow.dP_pl   = dP_pl;           % mmHg, calculated pleural swing
flow.VT      = VT;              % L
flow.passes  = pass;
end


function [flow, VT] = solve_once(p, lung, L_total, dP_tree_fn, dP_extra_fn, dP_pl)
P_pl_fn = @(t) pleural_pressure(t, p, lung, dP_pl);
rhs = @(t, y) [y(2); ...
    (p.p_atm - lung.P_alv_fn(t, y(1), P_pl_fn(t)) ...
     - dP_extra_fn(y(2)) - dP_tree_fn(y(2))) / L_total];

n  = p.n_time;
t_all = linspace(0, p.n_breaths * p.t_cycle, p.n_breaths * (n - 1) + 1)';
opts  = odeset('RelTol', 1e-8, 'AbsTol', [1e-10, 1e-10]);
[t_all, Y] = ode15s(rhs, t_all, [lung.V_FRC; 0], opts);

last = numel(t_all) - n + 1 : numel(t_all);           % final breath
prev = last - (n - 1);                                 % breath before it
flow.periodic_err = max(abs(Y(last, 1) - Y(prev, 1)));   % L

V_A = Y(last, 1);  Q_V = Y(last, 2);
P_pl = zeros(n, 1); P_alv = zeros(n, 1); dQ = zeros(n, 1);
for j = 1:n
    tj = t_all(last(j));
    P_pl(j)  = P_pl_fn(tj);
    P_alv(j) = lung.P_alv_fn(tj, V_A(j), P_pl(j));
    dy       = rhs(tj, Y(last(j), :)');
    dQ(j)    = dy(2);
end

% Flow lags the drive (time constant R*C), so rotate the periodic breath to
% start where flow turns inward: time = 0 is the start of inspiration.
u     = 1:n-1;
start = find(Q_V(u) < 0 & Q_V([2:n-1, 1]) >= 0, 1) + 1;
if isempty(start) || start > n-1, start = 1; end
order = [start:n-1, 1:start-1, start];

flow.time    = t_all(last) - t_all(last(1));
flow.Q_V     = Q_V(order);
flow.dQ_V_dt = dQ(order);
flow.V_A     = V_A(order);
flow.P_alv   = P_alv(order);
flow.P_pl    = P_pl(order);
VT = trapz(flow.time, max(flow.Q_V, 0));
end


function P = pleural_pressure(t, p, lung, dP_pl)
% Muscle drive [mmHg gauge] = P_pl_FRC + dP_pl * s(t).
% s(t) goes from 0 (FRC) to 1 (end of inspiration): lung.shape if supplied,
% otherwise a half-cosine rise over t_in and fall over t_out.
% dP_pl (the size of the swing) is calculated by coupled_breathing so that
% the solved tidal volume equals p.tidal_volume.
if isempty(lung.shape)
    tc = mod(t, p.t_cycle);
    if tc <= p.t_in
        s = (1 - cos(pi * tc / p.t_in)) / 2;
    else
        s = (1 + cos(pi * (tc - p.t_in) / p.t_out)) / 2;
    end
else
    tp = mod(t, lung.shape(end, 1));
    s  = interp1(lung.shape(:, 1), lung.shape(:, 2), tp, 'linear');
end
P = lung.P_pl_FRC + dP_pl * s;
end


function dP = generation_drops(Q_V, p, g)
% Resistive pressure drop of each generation in g.
%   Q_V [L/s] (vector, signed). Returns dP [mmHg], numel(Q_V) x numel(g.k).
Q_V = Q_V(:);
dP  = zeros(numel(Q_V), numel(g.k));
for j = 1:numel(Q_V)
    dP(j, :) = resistive_drop(Q_V(j) * 1e-3, g.d, g.l, g.n, g.R_pois_par, ...
                              g.wom_ratio, p.rho_air, p.mu_air, p.use_pedley)' / p.mmHg;
end
end


function dP = resistive_drop(Q, d, l, n, R_pois_par, wom_ratio, rho, mu, use_pedley)
% Viscous pressure drop across each generation (SI).
%   Q [m^3/s, signed], geometry in m. Returns dP [Pa] per generation, sign of Q.
% R = R_Poiseuille * max(Womersley ratio, Pedley ratio, 1)
%   Pedley, Schroter & Sudlow (1971): R/R_Pois = 0.327 sqrt(Re d / L)
%   Re = rho u d / mu, u = |Q| / total area of the generation (continuity)
A   = n .* pi .* (d/2).^2;
Re  = rho * (abs(Q) ./ A) .* d / mu;
ped = 0.327 * sqrt(Re .* d ./ l);
if use_pedley
    ratio = max(max(wom_ratio, ped), 1);
else
    ratio = wom_ratio;
end
dP = R_pois_par .* ratio * Q;
end


function g = weibel_geometry(p, gens)
% Geometry and flow-independent impedance for a set of Weibel generations
% (symmetric dichotomy, n = 2^k tubes per generation). Returns struct g:
%   k, n          generation numbers and tube counts
%   d, l          diameter and length of one tube [m]
%   area, vol     total cross-section [m^2] and volume [m^3] per generation
%   R_pois_par, wom_ratio   resistance terms (SI, see womersley_terms)
%   L_gen         inertance per generation [mmHg s^2/L];  L = sum(L_gen)
%   Wo            Womersley number per generation
omega  = 2*pi / p.t_cycle;
g.k    = gens(:);
g.n    = 2.^g.k;
g.d    = p.weibel_d_cm(g.k + 1)' / 100;
g.l    = p.weibel_l_cm(g.k + 1)' / 100;
g.area = g.n .* pi .* (g.d/2).^2;
g.vol  = g.area .* g.l;
[g.R_pois_par, g.wom_ratio, L_par] = womersley_terms(g.d, g.l, g.n, ...
                                         p.rho_air, p.mu_air, omega);
g.L_gen = L_par * 1e-3 / p.mmHg;      % Pa s^2/m^3 -> mmHg s^2/L
g.L     = sum(g.L_gen);
g.Wo    = (g.d/2) .* sqrt(p.rho_air * omega / p.mu_air);
end


function [R_pois_par, wom_ratio, L_par] = womersley_terms(d, l, n, rho, mu, omega)
% Flow-independent impedance of each generation (SI).
%   d, l [m], n tubes in parallel; rho [kg/m^3], mu [Pa s], omega [rad/s].
% Womersley's oscillatory solution of the Navier-Stokes equations in a rigid
% tube (Bessel functions): Z = i w rho L / (pi r^2 (1 - F10)),
%   F10 = 2 J1(Lam) / (Lam J0(Lam)),  Lam = i^(3/2) Wo,  Wo = r sqrt(rho w / mu).
% Outputs (per generation, n tubes in parallel):
%   R_pois_par [Pa s/m^3]  Hagen-Poiseuille resistance 8 mu L / (pi r^4) / n
%   wom_ratio  [-]         Re(Z) / R_Poiseuille
%   L_par      [Pa s^2/m^3] inertance Im(Z)/omega / n
r          = d / 2;
Wo         = r .* sqrt(rho * omega / mu);
R_pois     = 8 * mu .* l ./ (pi * r.^4);
Lam        = Wo * 1i^(3/2);
F10        = 2 * besselj(1, Lam) ./ (Lam .* besselj(0, Lam));
Z          = 1i * omega * rho .* l ./ (pi * r.^2) ./ (1 - F10);
wom_ratio  = real(Z) ./ R_pois;
R_pois_par = R_pois ./ n;
L_par      = imag(Z) / omega ./ n;
end


function gas = segment_transport(time, Q_V, V_segs, c_top, C_bottom_fn, n_breaths, c_init)
% Gas along one chain of well-mixed segments.
%   time, Q_V   shared time grid [s] and flow [L/s] (+ = toward the alveoli)
%   V_segs      segment volumes [L], segment 1 = trachea entry, end = Gen-16 exit
%   c_top       1 x 4 gas entering at the trachea on inspiration [mol/m^3]
%   C_bottom_fn @(t) -> 1 x 4 gas entering from the alveoli on expiration
%   c_init      n_seg x 4 initial contents (end-expiration)
% Species mass balance on each well-mixed segment (in - out, tanks in series):
%   inspiration: V_j dC_j/dt = Q_V (C_{j-1} - C_j),  C_0 = c_top
%   expiration:  V_j dC_j/dt = |Q_V| (C_{j+1} - C_j), C_{n+1} = C_bottom(t)
% As segments shrink this is the advection equation dC/dt + Q dC/dV = 0.
% Solved with ode45; repeated n_breaths times to reach periodic steady state.
% Output gas.C is numel(time) x n_seg x 4 for the final breath.
V_segs = V_segs(:);
n_seg  = numel(V_segs);
n_sp   = size(c_init, 2);
opts   = odeset('RelTol', 1e-6, 'AbsTol', 1e-9, 'MaxStep', min(diff(time)));
rhs    = @(t, y) segment_rhs(t, y, time, Q_V, V_segs, n_sp, c_top, C_bottom_fn);

y0 = c_init(:);
gas.y_start_prev = y0;
for b = 1:n_breaths
    gas.y_start_prev = y0;
    [~, Y] = ode45(rhs, time, y0, opts);
    y0 = Y(end, :)';
end
gas.y_start_last = gas.y_start_prev;
gas.y_end_last   = Y(end, :)';
gas.C = reshape(Y, numel(time), n_seg, n_sp);
end


function dydt = segment_rhs(t, y, time, Q_V, V_segs, n_sp, c_top, C_bottom_fn)
q = interp1(time, Q_V, t, 'linear', 'extrap');
C = reshape(y, numel(V_segs), n_sp);
if q >= 0
    upstream = [c_top; C(1:end-1, :)];
else
    upstream = [C(2:end, :); C_bottom_fn(t)];
end
dCdt = abs(q) ./ V_segs .* (upstream - C);
dydt = dCdt(:);
end


%% =====================================================================
%% OUTPUT HELPERS: summary and dashboard
%% =====================================================================

function print_summary(out)
% Main results (what run_airway.m printed). All pressures mmHg.
p = out.meta.params;
[~, ip] = max(out.Q_V);
fprintf('%s | lung: %s\n', p.version, out.lung_source);
fprintf('VT %.1f mL | peak Q_V %.3f L/s | breath %.0f s\n', out.VT*1e3, max(out.Q_V), p.t_cycle);
if isfield(out.calibration, 'R_tree')
    fprintf('K1 (nose-larynx) %.2f mmHg/(L/s); tree %.2f; total %.2f\n', ...
        out.K1, out.calibration.R_tree, out.calibration.R_total);
end
fprintf('Alveolar P %.2f to %.2f mmHg | pleural P %.2f to %.2f mmHg (calculated)\n', ...
    min(out.P_alv_mmHg) - p.p_atm, max(out.P_alv_mmHg) - p.p_atm, ...
    max(out.P_pl_mmHg), min(out.P_pl_mmHg));
fprintf('Drop at peak flow: nose-larynx %.3f | Gens 0-4 %.3f | Gens 5-16 %.3f mmHg\n', ...
    p.p_atm - out.p_trach_mmHg(ip), out.P_upper_mmHg(ip,1) - out.P_upper_mmHg(ip,end), ...
    out.P_lower_mmHg(ip,1) - out.P_lower_mmHg(ip,end));
fprintf('Dead space in model %.1f mL = %.0f extrathoracic + %.1f (J) + %.1f (Anna, %s); %d segments\n', ...
    out.V_D_model*1e3, p.V_extra*1e3, out.V_D_up*1e3, out.V_D_anna*1e3, ...
    p.lower_volume_source, numel(out.V_segs));
fprintf('  = %.0f%% of VT (agreed 0.3*VT = %.0f mL) | alveolar ventilation %.2f L/min\n', ...
    100*out.V_D_model/out.VT, out.measured_dead_space_vol*1e3, ...
    (out.VT - out.V_D_model) * 60/p.t_cycle);
fprintf('Anna''s section: pressure %s, mixing %s\n', p.lower_pressure_mode, p.lower_mixing);
if ~out.has_gas
    fprintf('No alveolar gas supplied (lung.C_alv_fn): flow and pressures only\n');
end
end


function plot_dashboard(out)
% Dashboard. All pressures in mmHg. No black lines (team request):
% reference lines orange, extra series teal.
p      = out.meta.params;
orange = [0.93 0.49 0.07];
teal   = [0.00 0.62 0.62];
t      = out.time;
to_mm  = @(C) C * p.r_gas * p.t_body / p.mmHg;     % mol/m^3 -> mmHg
i_sw   = find(out.Q_V(2:end) < 0, 1) + 1;          % where flow turns outward
t_sw   = t(i_sw);

figure('Name', 'Airway model (Gens 0-16)', 'Position', [100 100 1100 800]);

subplot(2, 3, 1);
plot(t, out.Q_V, 'b-', 'LineWidth', 1.8);
ref_line('yline', 0, '--', '', orange);
xlabel('Time (s)'); ylabel('Q_V (L/s)'); grid on;
title(sprintf('Tracheal flow (V_T = %.0f mL)', out.VT*1e3));

subplot(2, 3, 2);
plot(t, out.alv_gas_volume - out.alv_gas_volume(1), 'b-', 'LineWidth', 1.8);
xlabel('Time (s)'); ylabel('V_A change (L)'); grid on; title('Lung volume');

subplot(2, 3, 3);
plot(t, out.P_alv_mmHg - p.p_atm, 'r-', 'LineWidth', 1.8); hold on;
plot(t, out.P_pl_mmHg, 'm-', 'LineWidth', 1.8);
ref_line('yline', 0, '--', '', orange);
xlabel('Time (s)'); ylabel('mmHg (gauge)'); grid on;
legend('Alveolar', 'Pleural (calculated)', 'Location', 'best');
title('Lung pressures');

subplot(2, 3, 4);
plot(t, p.p_atm - out.p_trach_mmHg, '-', 'Color', teal, 'LineWidth', 1.8); hold on;
plot(t, p.p_atm - out.p_gen4_mmHg, 'r--', 'LineWidth', 1.8);
plot(t, p.p_atm - out.P_lower_mmHg(:, end), 'm-', 'LineWidth', 1.8);
xlabel('Time (s)'); ylabel('P_{atm} - P (mmHg)'); grid on;
legend('Trachea entry', 'Gen 4 exit (J -> Anna)', 'Gen 16 exit', 'Location', 'best');
title('Pressure drop down the airway');

subplot(2, 3, 5);
if out.has_gas
    plot(t, to_mm(out.C_trach(:, 2)), '-', 'Color', teal, 'LineWidth', 1.8); hold on;
    plot(t, to_mm(out.C_gen4(:, 2)),  'r-', 'LineWidth', 1.8);
    plot(t, to_mm(out.C_gen16(:, 2)), 'm-', 'LineWidth', 1.8);
    ref_line('xline', t_sw, ':', 'insp | exp', orange);
    xlabel('Time (s)'); ylabel('P_{CO2} (mmHg)'); grid on;
    legend('Trachea entry', 'Gen 4/5', 'Gen 16 exit', 'Location', 'east');
else
    axis([0 1 0 1]);  axis off;
    text(0.5, 0.5, 'No alveolar gas supplied (lung.C_alv_fn)', ...
         'HorizontalAlignment', 'center', 'Interpreter', 'none');
end
title('Dead-space washout (CO_2)');

subplot(2, 3, 6);
g  = [out.geometry.upper.k; out.geometry.lower.k];
Wo = [out.geometry.upper.Wo; out.geometry.lower.Wo];
hb = bar(g, Wo, 'FaceColor', [0.8 0.3 0.3]); hold on;
try, set(hb, 'FaceAlpha', 0.6); catch, end          % Octave bars have no FaceAlpha
ref_line('yline', 1, '--', 'Wo = 1', orange);
xlabel('Generation'); ylabel('Womersley number'); grid on;
title('Unsteadiness by generation');
end


function ref_line(kind, v, style, label, color)
% Orange reference line: yline / xline in MATLAB (R2018b+); a plain line where
% those functions do not exist (e.g. Octave).
if exist(kind) > 0 %#ok<EXIST>
    if isempty(label)
        feval(kind, v, style, 'Color', color, 'LineWidth', 1.5);
    else
        feval(kind, v, style, label, 'Color', color, 'LineWidth', 1.5);
    end
else
    hold on;
    if strcmp(kind, 'yline')
        plot(xlim, [v v], style, 'Color', color, 'LineWidth', 1.5);
    else
        plot([v v], ylim, style, 'Color', color, 'LineWidth', 1.5);
    end
end
end
