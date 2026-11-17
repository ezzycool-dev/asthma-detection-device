# Respiratory system: whole-team merge

One folder, one script: `run_respiratory`. Each subteam owns one folder and
hands values across through the fields below. Units everywhere: **pressure
mmHg** (absolute unless the name says gauge), **flow L/s** (+ = inspiration),
**volume L**, **time s**, **gas mol/m³** (columns O2 CO2 N2 H2O).

```text
run_respiratory.m        the script you run
respiratory_system.m     connects the subsystems, in order
INTERFACES.md            this file
airway/                  J + Anna, Gens 0-16 (airway-v0.4, 10 tests pass)
mechanics/               MECHANICS subteam - mechanics_stub.m until the real model arrives
gas_exchange/            MEMBRANE / CAPILLARY subteam - wraps the Oct 14 draft
gas_exchange/drafts/     the draft exactly as sent (not on the path)
tests/test_system.m      connection checks (must pass) + physiology checks (WARN while drafts)
```

## Order of solving

1. **Mechanics + airway** solve one flow Q(t) with VT fixed at 500 mL; the
   pleural pressure swing is calculated.
2. **Gas exchange** takes alveolar volume, alveolar ventilation and inspired
   gas from step 1 and returns alveolar gas.
3. **Airway again** with that alveolar gas, so exhaled gas comes from the
   membrane model. Flow and pressures don't depend on gas, so they're identical
   in both passes (check C6).

## Mechanics: what to provide

`mech = mechanics_model(p)` returning:

| Field | Unit | Meaning |
| --- | --- | --- |
| `C_L` | L/mmHg | lung compliance |
| `V_FRC` | L | functional residual capacity |
| `P_pl_FRC` | mmHg gauge | pleural pressure at FRC (start of inspiration) |
| `shape` | [t (s), 0–1] or `[]` | shape of the muscle drive; its size is calculated so VT = 500 mL |
| `P_alv_fn` | `@(t, V_A, P_pl)` → mmHg absolute | alveolar pressure |
| `source` | text | label printed in the summary |

Swap one line in `run_respiratory.m`: `mech = mechanics_model(p);`.
Receives (in `sys.airway`): `time, Q_V, dQ_V_dt, alv_gas_volume, P_alv_mmHg, P_pl_mmHg`.

Mechanics should **not** set the pleural pressure swing size or the tidal
volume as well. With VT fixed, the swing follows from compliance plus
resistance; setting both over-determines the system.

## Gas exchange: what to provide

The physics is in two files. Replace them with the final version:

- `gas_exchange/membrane_ode.m`: the ODE right-hand side
- `gas_exchange/gas_exchange_params.m`: its constants, each with a source

`gas_exchange.m` does the connecting and should not need changes. If the final
model gains states (e.g. a capillary compartment), update the solve and
package sections there.

| Receives from the airway | Unit |
| --- | --- |
| `Va` = mean alveolar volume over a breath | L |
| `Qi` = alveolar ventilation (VT − VD)/T = 5.25 L/min | L/s |
| `Foi`, `Fci` = fresh tracheal O2, CO2 as fractions of dry gas | – |

| Returns | Unit |
| --- | --- |
| `C_alv_fn(t)` → 1 × 4 | mol/m³ |
| `P_alv_end`, `PAO2`, `PACO2` | mmHg |
| `VO2_mL_min`, `VCO2_mL_min` | mL/min |

Set `g.inputs = 'draft'` to reproduce the draft on its own numbers
(Va 3.0 L, Qi 4 L/min).

## Status (Oct 14, before the merge)

All 7 connection checks pass. The physiology checks give WARN because of the
membrane draft:

| | Model | Guyton |
| --- | --- | --- |
| Alveolar PO2 | 40.2 mmHg | 104 |
| Alveolar PCO2 | 46.0 mmHg | 40 |
| O2 uptake | 516 mL/min | ~250 |
| CO2 output | 55 mL/min | ~200 |

**Why (for the membrane subteam):** within about 1 s the alveolar gas
equilibrates with the fixed venous blood (Po 40, Pc 46). Two causes:

1. **Diffusing capacity is too large.** With the draft's `1e-5` factor,
   D_O2 = 2772 mL/(min·mmHg) and D_CO2 = 55 440. Guyton Ch. 40 gives about
   21 and 400–450. The `1e-5` has no derivation, and the units of `Ko` and `Kc`
   aren't stated. If they are Krogh's mL·cm⁻¹·min⁻¹·atm⁻¹, the exact
   conversion from A in m² and T in m to L/(s·mmHg) is 2.19×10⁻⁶.
2. **Blood is fixed at venous values**, so there is no capillary transit. Real
   blood equilibrates along the capillary, and the mean gradient is far smaller
   than 104 − 40.

## Open citations

- `airway/airway_params.m`: `anna_C_ref = 75` mL/mmHg and `anna_V_ref_mL = 6000`
  mL in the new wall-compliance formula (1.553 mL/mmHg). Only affects Anna's
  reported volume.
- `gas_exchange/gas_exchange_params.m`: `Ko`, `Kc`, `unit_conversion`.

## Merge-night checklist

1. Put each subteam's files in its folder; keep their originals in a `drafts/`
   or `*_original/` subfolder.
2. Convert units at the boundary to the table above (cmH2O → mmHg: × 0.7356).
3. Swap the stub line in `run_respiratory.m`.
4. Run `addpath('tests'); test_system();`: all C-checks PASS.
5. Run `cd airway; addpath('tests'); test_airway();`: 10 of 10.
6. Run `run_respiratory` once in MATLAB to see the plots (Octave skips them).
