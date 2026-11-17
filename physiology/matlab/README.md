# Respiratory airway model (MATLAB)

This is the physiology model our team built before the early-warning device. It
models airflow, pressure and dead-space gas transport through the conducting
airway (Weibel generations 0-16). The device's design draws on it: asthma
narrows the mid-sized bronchi (roughly Gens 3-10), and this model shows how
that narrowing changes resistance, breathing effort and exhaled gas.

| File | What it is | Author |
| --- | --- | --- |
| `airway_model.m` | Merged airway model, Gens 0-16, one file. Solves one periodic breath with tidal volume fixed at 500 mL; pleural pressure is calculated. | Gens 0-4: Jana Robert-Oragbon. Gens 5-16: Anna |
| `upper_airway_gens0_4.m` | Standalone upper-airway model (trachea to Gen 4): Womersley/Pedley resistance, coupled airway-lung flow, dead-space washout | Jana Robert-Oragbon |
| `INTERFACES.md` | How the subteams' models connect (units, inputs, outputs) | Team |
| `CHANGELOG_ANNA.md` | How the Gens 5-16 code was merged, line by line | Team |

## Run it

```matlab
% Standalone upper airway (uses Guyton placeholder values for the lung)
upper_airway_gens0_4

% Merged model: needs a lung struct from the mechanics model
p    = airway_model('params');
lung = struct('V_FRC', 2.3, 'P_pl_FRC', -3.68, ...
              'P_alv_fn', @(t, V, Ppl) 760 + Ppl + 3.68 + (V - 2.3) / 0.272);
out  = airway_model(lung, p);
airway_model('summary', out);
airway_model('plot', out);
```

## Key physics

- Hagen-Poiseuille resistance per generation, scaled by Womersley (oscillatory flow) and Pedley (entrance flow) corrections; generations in series, branches in parallel
- Momentum balance per generation: $P_k - P_{k+1} = R_k Q + L_k \, dQ/dt$
- Coupled airway-lung ODEs solved with `ode15s`; tidal volume fixed at 500 mL
- Dead space 0.3 x VT = 150 mL, gas transport as a chain of well-mixed segments

Units throughout: pressure mmHg, flow L/s (+ = inspiration), volume L, gas mol/m^3.
Sources: Guyton & Hall; Systems Physiology; Weibel model A as tabulated in
Murayama et al., J Drug Deliv 2019; Pedley, Schroter & Sudlow 1971.
