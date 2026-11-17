# Privacy by design

These are design commitments for the device and app. The research code in this
repository only processes the anonymised AAMOS-00 dataset.

## Raw data never leaves the phone

The app would train with **federated learning**. Each phone updates the model
on its own data, and only the model update is sent to be combined with other
users' updates. Heart rate, biomarker readings, wheeze audio features and
attack history stay on the device.

- Wheeze detection runs on the device and keeps only a score, never audio.
- Personal baselines (median and spread per signal, day and night) are computed and stored on the phone.

## Opt-in only, explained first

Some features are off by default. Each one turns on only after a plain-language
screen explains what is shared, with whom, and how to turn it off:

| Feature | Default | What it shares |
| --- | --- | --- |
| Location-based triggers (pollen, air quality) | Off | Approximate location, used on the phone to look up local conditions |
| Sharing with a care provider | Off | Summaries the user picks (alerts, attack log), sent to the provider they choose |
| Emergency services (EMS) call on a severe prediction | Off | Location and alert, after a 45-second countdown the user can cancel |
| Contributing model updates to federated training | Off | Model updates only, no raw data |

## Research data

- AAMOS-00 is used under Edinburgh DataShare's terms and is not redistributed (see `data/README.md`).
- `data/raw/` and `outputs/` are git-ignored.
