# Architecture and design decisions

## Device concept

| Part | Measures | Why |
| --- | --- | --- |
| Implanted sensor (interstitial fluid) | Histamine | Mast-cell release is the earliest allergic signal, minutes before symptoms |
| Implanted sensor (plasma) | Sphingosine-1-phosphate (S1P) | Rises over hours in allergic asthma; covers late-phase responses |
| Smartwatch | Heart rate, activity, sleep | Context and a non-invasive signal |
| Phone microphone / wearable | Respiratory rate, wheeze score | Direct airway signs |

## Pipeline (one step per module)

| Step | Module | What happens |
| --- | --- | --- |
| 1 | `data.py` | Load AAMOS-00, build a gap-free 1-minute grid per person, score signal quality |
| 2 | `labels.py` | Turn inhaler, peak flow and questionnaires into dated attack episodes with ATS/ERS severity |
| 3 | `synthetic.py` | Add histamine, S1P, respiratory rate and wheeze around real attacks, plus decoys and sensor dropouts |
| 4 | `baseline.py` | Personal baseline per signal, day and night: median and MAD over the previous 14 days only, blended with a population prior while data builds up; attack days and 48 h after are excluded |
| 5 | `features.py` | Causal features: z-score and % change from baseline, rate of change, variability, personal and population thresholds, activity and sleep context, profile |
| 6 | `dataset.py` | Targets for 15 min / 1 h / 6 h and severity; drop minutes during attacks; thin quiet minutes for training |
| 7 | `models.py` | One LightGBM model per head, class-weighted |
| 8 | `evaluate.py` | Leave-one-person-out; thresholds tuned on held-back calibration users for 90% event sensitivity |
| 9 | `alerts.py` | Alert with cooldown and escalation; opt-in EMS countdown |
| 10 | `explain.py` | Top contributing features as plain-language "why now" |

## Key decisions

| Decision | Choice | Reason |
| --- | --- | --- |
| Output | Likelihood (15 min, 1 h, 6 h) and severity (moderate+, severe) | Users need both "when" and "how bad" |
| Severity labels | ATS/ERS 2009 | Standard clinical definitions |
| Baseline window | 14 days, before the current day only | Matches the AAMOS-00 analysis; avoids look-ahead |
| Robust statistics | Median and MAD | Single spikes do not shift the baseline |
| First model | Gradient-boosted trees | Works on small tabular data, fast, explainable |
| Validation | Leave one person out | Measures performance for a brand-new user |
| Alert tuning | 90% of attacks caught on calibration users | Missing an attack costs more than a false alarm |
| Comparators | HR-only model and the 2-of-3 rule | Shows what the biomarkers add |
| Privacy | Federated learning; sensitive features opt-in | Raw data never leaves the phone |

## Roadmap

- Train the two-branch GRU in `gru.py` (fast branch: minute signals; slow branch: hourly trends) and compare with the trees
- Replace synthetic biomarkers with bench sensor data when available
- Tune the false-alarm budget with user feedback
- On-device inference and a federated training prototype
