# Decision log

Design decisions for v0.2, with the reason for each. Items marked
**default** were not settled by the team; they are the working assumption the
code uses until someone changes them (each is a config value).

## Device and inputs

| Decision | Choice | Why |
| --- | --- | --- |
| Biomarker sampling | Prompted finger-prick test, not continuous implant (Nov 17-18) | Longer device life, less pain; the watch is cheap at spotting change, the test is good at confirming it |
| Sample | Plasma for both markers | Whole-blood histamine is mostly inside basophils at ~1000x plasma levels and hides the release |
| Test device | abbieSense-style electrochemical test; one test reads histamine and S1P | abbieSense detects histamine from a drop of blood in ~5-10 min; S1P detection is an assumption |
| Device output | 2 final values per test; averaging and reliability checks inside the device (Nov 19) | Matches abbieSense/eRapid: anti-fouling coating, blank electrode, multiple electrodes |
| Test logging | Device timestamps every test start (Nov 19) | Started + no values = device failure; no start = user didn't test |
| Wearable | Wrist, Apple Watch-style (**default**, Pugh matrix still comparing) | Team leaning; wrist optical signals get noisier with motion, handled by the quality score |
| Inputs | HR, RR, SpO2, steps, activity; wheeze dropped (Nov 18) | Wheeze needs a microphone the wearable may not have |
| SpO2 | Sparse input: latest value + time since reading; on-demand reading when risk rises (Nov 19) | Apple Watch measures SpO2 only occasionally |

## App logic

| Decision | Choice | Why |
| --- | --- | --- |
| Tests per prompt | One; a second at 45-60 min only if the first is high | S1P rise is seen at 45 min in people who go on to a late reaction |
| Prompt limits | No daily maximum; quiet period after a normal test | Team decision |
| Manual tests | Any time, no limit; user-started flag | Users manage their own supplies |
| Normal test | Saved as a not-asthma example | The trigger learns the person and fires less over time |
| Retest | Only when a result clashes sharply with the watch | Glucose-meter practice: retest when the number doesn't fit |
| Exercise | Compare to normal for the activity; flag tests within 30 min of exercise | Exercise alone shouldn't prompt; exercise raises S1P |
| Night | No prompts in sleep hours; urgent tier always wakes; persistence delay; opt-in caregiver; morning check-in (Nov 19) | Dexcom/FreeStyle Libre approach |
| Sleep hours | From the watch's sleep detection, user can override (**default**) | No user setup needed |
| Severity | Blood test rise + SpO2 < 95% / < 92% | Guideline cut-offs (NAEPP, Australian Asthma Handbook, GINA 2026) |
| Lead time target | 15 min | Time to use an inhaler and follow the action plan |
| Alarm limits | Normal-test prompts ~1/day while learning; false attack alerts <= 1/week | Two costs now: a finger prick and trust |
| Non-allergic attacks | A normal test doesn't cancel the watch path: if watch risk stays high, keep watching and allow the urgent tier (**default**) | Histamine/S1P are allergy markers; a normal test can't rule out exercise or cold-air attacks |
| Medications | Collected at onboarding; antihistamine use is a profile feature (**default**) | Antihistamines lower measured histamine |

## Model and evaluation

| Decision | Choice | Why |
| --- | --- | --- |
| Outputs | Risk 15 min / 1 h / 6 h; moderate+; severe; second wave | Unchanged goal: time until attack and severity |
| Model | LightGBM per output; shallow GRU later | Small tabular data, explainable |
| Training data | AAMOS-00 + synthetic biomarker/RR/SpO2 curves, sampled only at simulated tests | No dataset pairs biomarkers with attacks |
| Adherence | 60-80% of prompts answered; stress test at 40% | One-off self-tests ~88% done; routine finger pricks 20-88% |
| Sensor timing | Result 10 min after prompt-to-start delay (**default**) | abbieSense reports ~5-10 min |
| Detection limit | Sensor resolves resting plasma levels (**default**); stress test with a 1 ng/mL histamine floor | Mairal-Lerga strip test LOD ~1 ng/mL is above resting plasma |
| Users | Adults (**default**) | AAMOS-00 is adults; children later |
| Evaluation | Leave-one-person-out; event-level; two alarm limits; vs HR-only, 2-of-3 rule, v0.1 | Honest new-user test |
| Privacy | Opt-in for all personal-data features; raw data never leaves the phone | Team principle |
