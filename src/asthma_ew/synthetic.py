"""Step 2: synthetic histamine, S1P, respiratory rate and wheeze-score signals.

No dataset pairs continuous biomarkers with attack labels, so we attach
physiologically shaped synthetic signals to REAL AAMOS-00 people and attack
times. Each attack gets an allergen exposure 5-30 min before onset:

  histamine - fast spike (plasma peak ~10 min after exposure), read by an
              interstitial-fluid sensor -> delayed and scaled
  S1P       - read in plasma; rises over ~45 min and stays up for hours, but
              only in "dual responders" (people who go on to a late response);
              the rise grows with attack severity. For dual responders, about
              half of attacks are LATE responses: the exposure and early
              histamine reaction happen 3-8 h before the attack, and S1P stays
              raised until it arrives (what the second-wave forecast learns)
  RR        - drifts up before onset, also rises with physical activity
  wheeze    - the 0-1 score a separate audio classifier would output; a late
              sign that appears around onset

Some exposures cause a histamine blip with no attack, so the model cannot
simply treat every spike as an attack.

All shapes and numbers come from configs/default.yaml.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

SEVERITY_SCALE = {1: 0.8, 2: 1.0, 3: 1.3}


def _spike(t: np.ndarray, start: float, rise: float, halflife: float) -> np.ndarray:
    """0 before `start`, linear rise to 1 over `rise` min, then exponential decay."""
    x = t - start
    out = np.zeros_like(t, dtype=float)
    up = (x >= 0) & (x < rise)
    out[up] = x[up] / rise
    down = x >= rise
    out[down] = 0.5 ** ((x[down] - rise) / halflife)
    return out


def _plateau(t: np.ndarray, start: float, rise: float, hold: float, fall: float) -> np.ndarray:
    """Rise over `rise`, hold for `hold`, fall back linearly over `fall` (minutes)."""
    x = t - start
    out = np.zeros_like(t, dtype=float)
    out = np.where((x >= 0) & (x < rise), x / rise, out)
    out = np.where((x >= rise) & (x < rise + hold), 1.0, out)
    tail = (x >= rise + hold) & (x < rise + hold + fall)
    out = np.where(tail, 1 - (x - rise - hold) / fall, out)
    return np.clip(out, 0, 1)


def user_profile(rng: np.random.Generator, cfg: dict) -> dict:
    """Random per-person physiology (baselines, dual-responder status)."""
    s = cfg["synthetic"]
    h, p, r = s["histamine"], s["s1p"], s["rr"]
    return {
        "hist_base": max(0.05, rng.normal(h["baseline_mean"], h["baseline_sd"])),
        "s1p_base": max(0.4, rng.normal(p["baseline_mean"], p["baseline_sd"])),
        "rr_day": rng.normal(r["day_mean"], 1.0),
        "rr_night": rng.normal(r["night_mean"], 1.0),
        "dual_responder": bool(rng.random() < p["dual_responder_prob"]),
    }


def generate(grid: pd.DataFrame, episodes: pd.DataFrame, cfg: dict, rng: np.random.Generator) -> pd.DataFrame:
    """Add histamine, s1p, rr, wheeze and their quality scores to one user's grid.

    Returns (grid_with_signals, profile) where profile holds the person's
    random physiology (kept for analysis only, never given to the model).
    """
    s = cfg["synthetic"]
    h, p, rr_cfg, wz = s["histamine"], s["s1p"], s["rr"], s["wheeze"]
    t = grid["t"].to_numpy(dtype=float)
    n = len(t)
    prof = user_profile(rng, cfg)
    minute_of_day = t % 1440

    hist = np.full(n, prof["hist_base"]) + h["circadian_amp"] * np.sin(2 * np.pi * minute_of_day / 1440)
    s1p = np.full(n, prof["s1p_base"])
    rr = np.where(grid["is_night"].to_numpy() == 1, prof["rr_night"], prof["rr_day"]).astype(float)
    wheeze = np.full(n, wz["base"])

    lead_lo, lead_hi = s["exposure_lead_min"]
    late_lo, late_hi = s["late_lead_hours"]
    for _, e in episodes.iterrows():
        k = SEVERITY_SCALE[int(e["severity"])]
        onset = float(e["onset_t"])
        late = prof["dual_responder"] and rng.random() < s["late_response_prob"]
        if late:  # early reaction hours before, then the late attack (the "second wave")
            exposure = onset - 60 * rng.uniform(late_lo, late_hi)
        else:
            exposure = onset - rng.uniform(lead_lo, lead_hi)
        peak = max(prof["hist_base"] * 1.5, rng.normal(h["peak_mean"], h["peak_sd"])) * k
        hist += (peak - prof["hist_base"]) * _spike(t, exposure, h["rise_min"], h["decay_halflife_min"])
        rise = max(0.05, rng.normal(p["rise_pct_mean"], p["rise_pct_sd"])) * k
        if not prof["dual_responder"]:
            rise *= 0.2
        hold = max(p["persist_hours"] * 60, onset - exposure + 120)  # S1P stays up through the attack
        s1p += prof["s1p_base"] * rise * _plateau(t, exposure, p["rise_min"], hold, 120)
        rr_start = max(exposure, onset - 60)  # breathing changes in the last hour before onset
        rr += rr_cfg["attack_rise"] * k * _plateau(t, rr_start, onset - rr_start + 30, 120, 240)
        wheeze += (wz["attack_peak"] * k - wz["base"]) * _plateau(t, onset, 30, 90, 180)

    # Exposures with no attack: a smaller histamine blip only
    weeks = n / (7 * 1440)
    for _ in range(rng.poisson(s["false_exposure_per_week"] * weeks)):
        start = rng.uniform(t[0], t[-1])
        blip = rng.uniform(0.3, 0.6) * (h["peak_mean"] - prof["hist_base"])
        hist += blip * _spike(t, start, h["rise_min"], h["decay_halflife_min"])

    # Activity raises RR (context the model must learn to discount)
    active = grid["activity"].isin(["walk", "running", "activity_high"]).to_numpy()
    rr += rr_cfg["activity_rise"] * active * rng.uniform(0.5, 1.0, n)

    # Plasma -> interstitial fluid for histamine: delay then scale
    delay = int(h["fluid_delay_min"])
    hist_isf = np.concatenate([np.full(delay, hist[0]), hist[:-delay]]) if delay > 0 else hist
    hist_isf = hist_isf * h["fluid_scale"]

    out = grid.copy()
    out["histamine"] = hist_isf + rng.normal(0, h["noise_sd"], n)
    out["s1p"] = s1p + rng.normal(0, p["noise_sd"], n)
    out["rr"] = rr + rng.normal(0, rr_cfg["sd"], n)
    out["wheeze"] = np.clip(wheeze + rng.normal(0, wz["noise_sd"], n), 0, 1)

    # Quality scores: implant sensors warm up for 60 min every 14 days and
    # drop out ~1% of minutes; wheeze audio is less reliable while moving;
    # RR comes from the watch, so it shares the HR quality.
    since_start = t - t[0]
    warmup = (since_start % (14 * 1440)) < 60
    for name in ["histamine", "s1p"]:
        q = np.where(warmup | (rng.random(n) < 0.01), 0.0, 1.0)
        out[f"q_{name}"] = q
        out.loc[q == 0, name] = np.nan
    out["q_rr"] = out["q_hr"]
    out.loc[out["q_rr"] == 0, "rr"] = np.nan
    out["q_wheeze"] = np.where(active, 0.6, 1.0)
    return out, prof
