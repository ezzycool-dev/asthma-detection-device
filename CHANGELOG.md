# Changelog

## v0.2.0 (2026-11-19): design update

Design and documentation release. No pipeline code changes; coding for the
new design starts in v0.3.

- New device design: wrist wearable runs continuously and prompts a
  finger-prick blood test (histamine + S1P, plasma) only when risk is high.
  Replaces the continuous implant assumed in v0.1.
- Wheeze removed as an input; SpO2 added as a sparse input.
- Blood test device returns 2 final values per test and logs every test start,
  so missed tests and device failures are told apart.
- Night mode following the Dexcom / FreeStyle Libre approach.
- New docs: `docs/design.md` (app and model flows), `docs/decisions.md`,
  `docs/sources.md`; new parameters in `configs/design_v0.2.yaml`.
- v0.1 results kept for reference; they describe the continuous design.

## v0.1.0 (2026-11-17)

First pipeline: AAMOS-00 labels, synthetic biomarkers, personal baselines,
LightGBM heads, leave-one-person-out evaluation.
