"""Step 3: personal day/night baselines with a population prior and guardrails.

For each signal, each person and each day, the baseline is built ONLY from the
previous 14 days (never the current or future days):

  typical value = median of the daily medians over the last 14 days
  normal spread = median of the daily spreads (1.4826 x MAD, a robust SD)

Day and night get separate baselines, because HR and RR drop in sleep and
histamine has a daily rhythm.

Guardrails:
  - only minutes with quality >= min_quality count
  - attack episodes and the 48 h after them are excluded, so attacks never
    become "normal"
  - for the first 14 days the personal value is blended with a population
    prior (personal weight = valid days / 14)
  - if the personal median drifts far from the population range, the
    population prior is used instead and the day is flagged
"""

from __future__ import annotations

import numpy as np
import pandas as pd

MAD_TO_SD = 1.4826


def exclusion_mask(t: np.ndarray, episodes: pd.DataFrame, cfg: dict) -> np.ndarray:
    """True for minutes inside an episode or within 48 h after it ends."""
    mask = np.zeros(len(t), dtype=bool)
    after = cfg["labels"]["exclude_after_hours"] * 60
    for _, e in episodes.iterrows():
        end = (int(e["end_day"]) + 1) * 1440 + after
        mask |= (t >= e["onset_t"]) & (t < end)
    return mask


def _mad_sd(x: pd.Series) -> float:
    x = x.dropna()
    if len(x) < 10:
        return np.nan
    return float(MAD_TO_SD * np.median(np.abs(x - np.median(x))))


def compute(grid: pd.DataFrame, episodes: pd.DataFrame, signals: list[str], cfg: dict) -> pd.DataFrame:
    """Return one row per (day, is_night) with baseline median/spread per signal."""
    b = cfg["baseline"]
    min_q = cfg["grid"]["min_quality"]
    excluded = exclusion_mask(grid["t"].to_numpy(), episodes, cfg)
    days = np.arange(grid["day"].min(), grid["day"].max() + 1)
    index = pd.MultiIndex.from_product([days, [0, 1]], names=["day", "is_night"])
    out = pd.DataFrame(index=index)

    for sig in signals:
        ok = (grid[f"q_{sig}"] >= min_q) & ~excluded & grid[sig].notna()
        g = grid.loc[ok, ["day", "is_night", sig]]
        daily = g.groupby(["day", "is_night"])[sig].agg(med="median", spread=_mad_sd)
        daily = daily.reindex(index)
        pers_med, pers_spread, n_days = [], [], []
        for night in (0, 1):
            d = daily.xs(night, level="is_night")
            past = d.shift(1)  # never use the current day
            pers_med.append(past["med"].rolling(b["window_days"], min_periods=1).median())
            pers_spread.append(past["spread"].rolling(b["window_days"], min_periods=1).median())
            n_days.append(past["med"].rolling(b["window_days"], min_periods=1).count())
        pm = pd.concat(pers_med, keys=[0, 1], names=["is_night"]).swaplevel().reindex(index)
        ps = pd.concat(pers_spread, keys=[0, 1], names=["is_night"]).swaplevel().reindex(index)
        nd = pd.concat(n_days, keys=[0, 1], names=["is_night"]).swaplevel().reindex(index).fillna(0)

        pop = b["population"][sig]
        pop_med = np.where(index.get_level_values("is_night") == 1, pop["night"][0], pop["day"][0])
        pop_sd = np.where(index.get_level_values("is_night") == 1, pop["night"][1], pop["day"][1])

        w = np.clip(nd.to_numpy() / b["blend_days"], 0, 1)
        drift = np.abs(pm.to_numpy() - pop_med) / pop_sd > b["drift_z"]
        w = np.where(np.isnan(pm.to_numpy()) | drift, 0.0, w)
        med = w * np.nan_to_num(pm.to_numpy()) + (1 - w) * pop_med
        spread = w * np.nan_to_num(ps.to_numpy(), nan=pop_sd) + (1 - w) * pop_sd
        spread = np.maximum(spread, 0.1 * pop_sd)  # avoid dividing by ~0

        out[f"{sig}_base"] = med
        out[f"{sig}_spread"] = spread
        out[f"{sig}_base_w"] = w
        out[f"{sig}_drift"] = drift.astype(int)
    return out.reset_index()
