# Data

## AAMOS-00 (real data, not included)

The real data comes from the AAMOS-00 study: 22 UK adults with asthma
monitored for up to 6 months with a smartwatch (Mi Band 3), smart inhaler,
smart peak flow meter and daily/weekly questionnaires.

The dataset is distributed by Edinburgh DataShare under its own terms, so it
is **not** committed here. To run the pipeline:

1. Download the anonymised dataset from Edinburgh DataShare:
   https://www.research.ed.ac.uk/en/datasets/aamos-00-study-predicting-asthma-attacks-using-connected-mobile-d/
2. Put the CSV files in `data/raw/aamos00/`:

```text
data/raw/aamos00/
  anonym_aamos00_patient_info.csv
  anonym_aamos00_smartwatch1.csv
  anonym_aamos00_smartwatch2.csv
  anonym_aamos00_smartwatch3.csv
  anonym_aamos00_smartinhaler.csv
  anonym_aamos00_peakflow.csv
  anonym_aamos00_dailyquestionnaire.csv
  anonym_aamos00_weeklyquestionnaire.csv
  anonym_aamos00_environment.csv
```

`data/raw/` is in `.gitignore`, so the files cannot be committed by accident.

Reference: Tsang KCH, Pinnock H, Wilson AM, Salvi D, Shah SA. *Home monitoring
with connected mobile devices for asthma attack prediction with machine
learning.* Scientific Data 10, 370 (2023). doi:10.1038/s41597-023-02241-9

## What is real and what is synthetic

| Signal | Source |
| --- | --- |
| Heart rate, steps, activity type | Real (AAMOS-00 smartwatch, 1-minute) |
| Attack timing and severity | Real (AAMOS-00 inhaler, peak flow, questionnaires) |
| Histamine, S1P | Synthetic, shaped from published allergen-challenge studies |
| Respiratory rate, wheeze score | Synthetic |

No dataset pairs continuous biomarkers with attack labels, which is why the
biomarker signals are generated (`src/asthma_ew/synthetic.py`). Results on this
semi-synthetic data test the pipeline and design choices; they are not
evidence of clinical performance.
