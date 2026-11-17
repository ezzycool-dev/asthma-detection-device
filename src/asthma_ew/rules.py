"""Comparison baseline: the simple 2-of-3 rule.

For each signal, three checks (the team's threshold / rate / proportion idea):
  threshold   above the personal threshold (z > 2)
  rate        rising over the last 15 min
  proportion  more than 50% above personal baseline (wheeze: +0.2 on the 0-1 score)

The rule alerts when any signal passes at least 2 of its 3 checks. The score is
the largest fraction of checks passed by any signal (0, 1/3, 2/3 or 1), so the
alert threshold is 2/3. The ML model has to beat this to be worth using.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

RULE_THRESHOLD = 2 / 3


def two_of_three_score(df: pd.DataFrame, signals: list[str]) -> np.ndarray:
    best = np.zeros(len(df))
    for sig in signals:
        threshold = df[f"{sig}_hi_personal"].fillna(0).to_numpy() > 0
        rate = df[f"{sig}_rate_15"].fillna(0).to_numpy() > 0
        if sig == "wheeze":
            proportion = df[f"{sig}_pct"].fillna(0).to_numpy() > 0.2
        else:
            proportion = df[f"{sig}_pct"].fillna(0).to_numpy() > 50
        best = np.maximum(best, (threshold.astype(int) + rate + proportion) / 3)
    return best
