# Data, labels and known limitations

## How attacks are labelled

Severity follows the ATS/ERS 2009 task force definitions (Reddel et al.,
*AJRCCM* 2009), applied to each person-day in AAMOS-00:

| Severity | Evidence that day |
| --- | --- |
| Severe | Oral steroids, ER visit or hospital admission (weekly questionnaire) |
| Moderate | Peak flow below 80% of personal best, or reliever puffs above $\max(2\times\text{usual}, \text{usual}+2)$, where usual is the median of the previous 14 days |
| Mild | Symptoms plus reliever use, without moderate evidence |

Neighbouring attack days (gap of 1 day or less) merge into one episode. Onset is the
earliest inhaler puff or low peak flow that day, otherwise noon. Severity is
the worst day in the episode.

On the real data this gives **200 episodes** (70 mild, 102 moderate, 28
severe). 106 have an hour-level onset time and 94 only a day.

## Known limitations

1. **Biomarkers are synthetic.** No public dataset pairs continuous histamine or S1P with attack labels. The generator follows published allergen-challenge shapes (early histamine spike; S1P rise in dual responders, late responses 3-8 h before onset), but the results test the pipeline and do not show clinical accuracy.
2. **Respiratory rate and wheeze are synthetic.** The Mi Band 3 in AAMOS-00 records heart rate, steps and activity only.
3. **Small cohort.** 22 adults; 20 have watch data, so the model uses 20.
4. **Onset times are coarse.** About half the episodes only have a day, which limits how much the 15-minute window can be trusted.
5. **Chronic symptoms.** One participant reports symptoms nearly every day, which the labelling rule turns into one 101-day mild episode. A real deployment would need a separate rule for chronic poor control.
6. **Weekly questionnaire timing.** Oral steroids and hospital visits are reported weekly, so their day is estimated (steroids placed 3 days before the report).
