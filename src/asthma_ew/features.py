"""Step 4: causal features, one row per minute.

"Causal" means every feature at minute t uses only data from minutes <= t,
because the phone never has future data. (Pandas `shift(k)` and trailing
`rolling` windows only look backwards.)

Per signal (hr, rr, wheeze, histamine, s1p):
  value        latest reading (carried forward up to 10 min)
  pct          % change from personal baseline        <- "proportion" check
  z            change in units of the person's normal spread
  rate_<k>     change per minute over the last k minutes  <- "rate" check
               (histamine: 5, 15 and 1440 min; others: 15 and 1440 min)
  sd60         variability over the last hour
  hi_personal  z above 2                               <- "threshold" check
  hi_pop       above a population "high" value (safety backstop)
  q            quality score 0..1

Context: steps over the last 10 min, active flag, asleep flag, night flag.
Profile: self-rated severity, age range, BMI range, age at diagnosis, smoker.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

ORDINALS = {
    "severity": {"Very mild": 0, "Mild": 1, "Moderate": 2, "Severe": 3, "Very severe": 4},
    "age_range": {"18-29yo": 0, "30-39yo": 1, "40-49yo": 2, "50+yo": 3},
    "bmi_range": {"Underweight": 0, "Normal": 1, "Pre-obesity": 2, "Obesity": 3},
    "age_diagnosed_range": {"0-6yo": 0, "7-11yo": 1, "12-18yo": 2, "19+yo": 3},
}


def profile_features(patient_row: pd.Series) -> dict:
    """Static profile features (AAMOS-00 proxies for the planned user profile)."""
    feats = {f"profile_{k}": m.get(patient_row.get(k), np.nan) for k, m in ORDINALS.items()}
    feats["profile_smoker"] = 0 if str(patient_row.get("smoker", "")).startswith("Never") else 1
    return feats


def build(grid: pd.DataFrame, base: pd.DataFrame, cfg: dict, profile: dict | None = None) -> pd.DataFrame:
    """Return the feature table for one user (same row order as `grid`)."""
    f_cfg = cfg["features"]
    g = grid.merge(base, on=["day", "is_night"], how="left")
    feats = {"user_key": g["user_key"].to_numpy(), "t": g["t"].to_numpy()}

    for sig in f_cfg["signals"]:
        v = g[sig].ffill(limit=10)
        med, spread = g[f"{sig}_base"], g[f"{sig}_spread"]
        z = (v - med) / spread
        feats[f"{sig}_value"] = v
        feats[f"{sig}_z"] = z
        feats[f"{sig}_pct"] = 100 * (v - med) / med.abs().clip(lower=1e-3) if sig != "wheeze" else v - med
        spans = f_cfg["rate_spans_min"].get(sig, f_cfg["rate_spans_min"]["default"])
        for k in spans:
            feats[f"{sig}_rate_{k}"] = (v - v.shift(k)) / k
        feats[f"{sig}_sd60"] = v.rolling(f_cfg["variability_window_min"], min_periods=10).std()
        feats[f"{sig}_hi_personal"] = (z > f_cfg["personal_threshold_z"]).astype(float)
        feats[f"{sig}_hi_pop"] = (v > f_cfg["population_high"][sig]).astype(float)
        feats[f"{sig}_q"] = g[f"q_{sig}"]
        feats[f"{sig}_base_w"] = g[f"{sig}_base_w"]

    feats["ctx_steps10"] = g["steps"].rolling(10, min_periods=1).sum()
    feats["ctx_active"] = g["activity"].isin(["walk", "running", "activity_high"]).astype(float)
    feats["ctx_asleep"] = (g["activity"] == "sleep").astype(float)
    feats["ctx_night"] = g["is_night"].astype(float)
    for k, val in (profile or {}).items():
        feats[k] = val
    out = pd.DataFrame(feats)
    num = out.columns.difference(["user_key", "t"])
    out[num] = out[num].astype("float32")
    return out


def feature_columns(df: pd.DataFrame, only: str | None = None) -> list[str]:
    """Model input columns. only="hr" keeps the HR-only comparator's inputs."""
    cols = [c for c in df.columns if c not in ("user_key", "t") and not c.startswith("y_") and not c.startswith("sev_")
            and c not in ("time_to_onset", "next_severity")]
    if only == "hr":
        cols = [c for c in cols if c.startswith(("hr_", "ctx_", "profile_"))]
    return cols
