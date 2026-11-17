# Change log for Anna — merging `simulate_bronchioles_gen5_16.m` (airway-v0.3)

Your original function and test script are kept **unchanged** in
`lower/anna_original/`. This log maps every part of them to the merged code.
"Team decision" = decided by J on Oct 11; each one has a switch so you can run
your original behaviour for comparison.

## What did not change

- Your Weibel table, all values **as published** (`p.anna_weibel_matrix`), including gen 7 area 4.1 and gen 9 area 9.65. Checked row by row against the source: all 12 rows match Table 1 of Murayama et al., *J Drug Deliv* 2019, Article ID 3921426, doi:10.1155/2019/3921426 (Weibel human model A, from the Annals of the ICRP).
- Your resistance law: Hagen–Poiseuille per generation, N branches in parallel (your lines 35–41).
- No gas inertia in Gens 5–16 (your model has none).
- Water vapour 47 mmHg, 37 °C, 100% RH, flow sign (+ = inhale), alveolar gas 100 / 40 / 573 / 47 mmHg.

## Line-by-line

| Your lines | What it did | Where it is now | Change |
| --- | --- | --- | --- |
| 1 | One function taking time, two boundary structs, pleural pressure, params, table | `lower/lower_geometry.m`, `lower_dP.m`, `lower_profile.m`, `lower_view.m` | Split into the three contract functions plus a results adapter |
| 8–23 | Default Weibel table, Gens 5–16 | `airway_params.m` → `p.anna_weibel_matrix` | None (values unchanged) |
| 24–25 | `N`, `dt` from your 0.01 s time vector | Shared time grid from the flow solver (100 points per 4 s breath) | Output grid only; the ODE solvers choose their own internal steps. Finer output: raise `p.n_time` |
| 27–34 | Extract columns; `V_baseline = 124.24` mL | `lower_geometry.m` (`g.d, g.l, g.n, g.area, g.vol`, `g.V_baseline_mL`) | Columns unchanged. **Team decision:** the gas volume of your section is 55.5 mL, your share of the agreed 0.3 × VT = 150 mL dead space (72 nose–larynx + 22.5 J + 55.5 you). Your 124.24 mL is still reported as `lower_view.geometry.V_baseline`; `p.lower_volume_source = 'weibel_table'` runs with it |
| 37 | `mu_air = 1.81e-5` hard-coded | `p.mu_air = 19.1e-6` Pa·s (Sys Phys Ch. 6.2, J's decision) | **Value change:** your R_total rises 5.5%, 0.0898 → 0.0947 mmHg/(L/s) |
| 38–41 | Poiseuille R per generation, summed, converted to mmHg·s/mL | `lower_geometry.m` → `g.R_gen`, `g.R_total` (mmHg/(L/s)); `lower_dP.m` = `g.R_total * Q_V` | Same formula; unit is yours × 1000. Your `R_total` (9.47e-5 mmHg·s/mL) is still in `lower_view.geometry.R_total` |
| 43–44 | `P_airway = P_atm + 0.8 sin(pi t/2)` | `lower_profile.m`, mode `'computed'` | **Team decision:** pressure now starts at J's Gen-4 exit and falls through your Poiseuille resistance to alveolar pressure. At peak inhale: −0.69 mmHg (Gen 5) → −0.73 mmHg (Gen 16). Your formula is mode `'anna_formula'` (+0.8 mmHg during inhale; fails test 3) |
| 46–47 | Wall-compliance volume, `C = 1.5` mL/mmHg | `lower_view.volume` | Same formula. Pleural pressure is now gauge on both sides of the subtraction (yours subtracted gauge pleural from absolute airway; the offset cancelled because you subtract the mean, so the method is unchanged) |
| 49–50 | `V_tidal = 500`; `Q = (500·pi/4) sin(pi t/2)` | J's calculated flow (`out.Q_V`) | **Team decision:** one flow for the whole airway. Same 500 mL and 4 s; peak 388 mL/s at ~1.0 s (yours 392.7 mL/s at 1.0 s) |
| 53–56 | Velocity per generation = Q / area | `lower_view.geometry.generation_velocities` | None (your areas) |
| 58–82 | One well-mixed compartment, explicit Euler, mix rate \|Q\|/V; N₂ = remainder | Shared gas chain: your 55.5 mL as 74 segments of 0.75 mL (`shared/segment_transport.m`, ode45) | **Team decision:** chain, which gives the sharp washout. Your single tank is `p.lower_mixing = 'single_tank'`. Inhaled gas now comes from J's last segment; exhaled gas from the alveolar stand-in. N₂ is transported like the other gases; PV = nRT is checked by test 5 |
| 84–104 | `sim_results` struct | `out.lower_view` | Same field names. Columns instead of rows. `partial_pressures` = volume-weighted mean over your segments; new `partial_pressures_exit` (gas leaving Gen 16 for Ryan), `pressure_gen5_entry`, `pressure_gen16_exit` |

## Your test script

- Line 137–138 passes `'full_cycle'` as the 6th argument, where the Weibel matrix goes. MATLAB then reads the text as the table: the run used a 99 mL airway with one "generation" numbered 102. Calling with 5 arguments (or your matrix) runs your default table.
- Checks 1 and 2 cannot fail (N₂ is computed as the remainder, so fractions sum to 1 and Dalton holds by construction), and check 5 always prints PASS. The merged `tests/test_airway.m` replaces them with ten checks that can fail.

## Switches (all in `airway_params.m`)

| Setting | Default (team decision) | Your original |
| --- | --- | --- |
| `p.lower_pressure_mode` | `'computed'` | `'anna_formula'` |
| `p.lower_mixing` | `'chain'` | `'single_tank'` |
| `p.lower_volume_source` | `'dead_space_share'` (55.5 mL) | `'weibel_table'` (124.24 mL) |
| `p.lower_include_inertance` | `false` | same |

## Open items

1. **Source for `airway_compliance = 1.5` mL/mmHg** (your test params). It only affects `lower_view.volume`.
