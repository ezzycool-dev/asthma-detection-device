"""Step 5: turn feature rows into training examples with targets.

For each minute t and each window H (15, 60, 360 min):
  y_<H> = 1 if the next attack onset is in (t, t + H], else 0

Severity targets describe that next attack (only used when y_360 = 1):
  sev_moderate = 1 if it is at least moderate
  sev_severe   = 1 if it is severe
(two stacked yes/no questions, which keeps the mild < moderate < severe order)

Minutes during an attack (from onset to the end of the episode, at least 6 h)
are dropped: the model must predict attacks, not detect ones already
happening.

Sampling: for training, every minute in the 6 h before an onset is kept and
quiet minutes are thinned to every 5th minute (they are near-duplicates). For
testing, every 5th minute is kept everywhere, so metrics reflect real use.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def add_targets(feats: pd.DataFrame, episodes: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    tc = cfg["targets"]
    t = feats["t"].to_numpy()
    eps = episodes.sort_values("onset_t")
    onsets = eps["onset_t"].to_numpy()
    sev = eps["severity"].to_numpy()

    if len(onsets) == 0:  # a person with no attacks: every minute is a negative example
        tto, next_sev = np.full(len(t), np.inf), np.zeros(len(t), dtype=int)
    else:
        idx = np.searchsorted(onsets, t, side="right")  # first onset strictly after t
        has_next = idx < len(onsets)
        tto = np.where(has_next, onsets[np.minimum(idx, len(onsets) - 1)] - t, np.inf)
        next_sev = np.where(has_next, sev[np.minimum(idx, len(sev) - 1)], 0)

    out = feats.copy()
    out["time_to_onset"] = tto.astype("float32")
    for h in tc["windows_min"]:
        out[f"y_{h}"] = ((tto > 0) & (tto <= h)).astype("int8")
    out["sev_moderate"] = (next_sev >= 2).astype("int8")
    out["sev_severe"] = (next_sev >= 3).astype("int8")

    during = np.zeros(len(t), dtype=bool)
    for _, e in eps.iterrows():
        end = max(e["onset_t"] + tc["exclude_after_onset_min"], (int(e["end_day"]) + 1) * 1440)
        during |= (t >= e["onset_t"]) & (t < end)
    return out[~during].reset_index(drop=True)


def sample(df: pd.DataFrame, cfg: dict, train: bool) -> pd.DataFrame:
    tc = cfg["targets"]
    every = tc["quiet_subsample_every"]
    regular = (df["t"] % every) == 0
    if not train:
        return df[regular].reset_index(drop=True)
    near = df["time_to_onset"] <= tc["near_attack_min"]
    return df[regular | near].reset_index(drop=True)
