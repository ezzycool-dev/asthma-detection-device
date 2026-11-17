# Results (leave-one-person-out, semi-synthetic data)
20 people, 121 attack episodes. Biomarker, RR and wheeze signals are synthetic; HR, activity and attack timing are real (AAMOS-00). These numbers test the pipeline and the design, not clinical performance.
## Attack likelihood
| window_min | model | auroc | auprc | event_sensitivity | allergy_event_sensitivity | median_lead_min | false_alarms_per_day |
|---|---|---|---|---|---|---|---|
| 15 | Full model | 0.78 | 0.07 | 0.63 | 0.49 | 10 | 34.35 |
| 15 | HR-only model | 0.49 | 0.00 | 0.31 | 0.26 | 10 | 49.27 |
| 15 | 2-of-3 rule | 0.73 | 0.01 | 0.55 | 0.51 | 10 | 19.66 |
| 60 | Full model | 0.77 | 0.06 | 0.86 | 0.82 | 50 | 23.97 |
| 60 | HR-only model | 0.53 | 0.00 | 0.69 | 0.64 | 60 | 30.44 |
| 60 | 2-of-3 rule | 0.63 | 0.01 | 0.88 | 0.90 | 40 | 19.56 |
| 360 | Full model | 0.68 | 0.28 | 0.77 | 0.77 | 335 | 15.09 |
| 360 | HR-only model | 0.49 | 0.03 | 0.60 | 0.36 | 350 | 29.46 |
| 360 | 2-of-3 rule | 0.60 | 0.04 | 1.00 | 1.00 | 330 | 18.91 |

## Same models at a fixed false-alarm budget
Each row uses the one shared threshold that catches the most attacks while staying within the budget. This traces the trade-off curve; it is not a threshold tuned for deployment.

| window_min | model | alarms/day budget | event_sensitivity | false_alarms_per_day | median_lead_min |
|---|---|---|---|---|---|
| 15 | Full model | 1 | 0.40 | 0.99 | 10 |
| 15 | Full model | 3 | 0.50 | 2.89 | 10 |
| 15 | HR-only model | 1 | 0.00 | 0.00 | - |
| 15 | HR-only model | 3 | 0.00 | 0.00 | - |
| 15 | 2-of-3 rule | 1 | 0.00 | 0.00 | - |
| 15 | 2-of-3 rule | 3 | 0.34 | 2.89 | 10 |
| 60 | Full model | 1 | 0.53 | 0.63 | 15 |
| 60 | Full model | 3 | 0.62 | 2.84 | 30 |
| 60 | HR-only model | 1 | 0.01 | 0.83 | 60 |
| 60 | HR-only model | 3 | 0.03 | 2.85 | 60 |
| 60 | 2-of-3 rule | 1 | 0.00 | 0.00 | - |
| 60 | 2-of-3 rule | 3 | 0.51 | 2.86 | 15 |
| 360 | Full model | 1 | 0.55 | 0.96 | 238 |
| 360 | Full model | 3 | 0.64 | 2.82 | 260 |
| 360 | HR-only model | 1 | 0.06 | 0.95 | 300 |
| 360 | HR-only model | 3 | 0.09 | 1.59 | 300 |
| 360 | 2-of-3 rule | 1 | 0.00 | 0.00 | - |
| 360 | 2-of-3 rule | 3 | 0.76 | 2.67 | 262 |

## Severity (minutes before an attack)
- At least moderate: AUROC 0.46
- Severe: AUROC 0.39

Per-person AUROC (60-min window): mean 0.70, SD 0.15, range 0.37-0.98

## Example "Why now?" explanation
15 min before an attack, P(attack within 60 min) = 0.99. Reasons:
- S1P is rising over the last 1440 min
- histamine is rising over the last 15 min
- histamine is +268% from your normal
