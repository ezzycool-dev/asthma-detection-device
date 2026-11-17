"""Step 8: "Why now?" explanations.

Every alert shows the few inputs that pushed the risk up the most, in plain
language. The tree model gives each feature's contribution to a prediction
(LightGBM `pred_contrib`), so no extra model is needed.
"""

from __future__ import annotations

import pandas as pd

NAMES = {"hr": "heart rate", "rr": "breathing rate", "wheeze": "wheeze score", "histamine": "histamine", "s1p": "S1P"}


def describe(feature: str, value: float) -> str:
    sig, _, kind = feature.partition("_")
    name = NAMES.get(sig)
    if name is None:
        if feature == "ctx_active":
            return "you are not moving much" if value < 0.5 else "you are active"
        if feature == "ctx_night":
            return "it is night-time"
        return feature.replace("_", " ")
    if kind == "z":
        return f"{name} is {value:+.1f} spreads from your normal"
    if kind == "pct":
        return f"{name} is {value:+.0f}% from your normal" if sig != "wheeze" else f"{name} is {value:+.2f} above your normal"
    if kind.startswith("rate_"):
        span = kind.split("_")[1]
        return f"{name} is {'rising' if value > 0 else 'falling'} over the last {span} min"
    if kind == "hi_personal":
        return f"{name} is above your personal threshold"
    if kind == "hi_pop":
        return f"{name} is above the general high range"
    if kind == "sd60":
        return f"{name} has been unusually changeable over the last hour"
    if kind == "value":
        return f"{name} level is {value:.2f}" if sig in ("histamine", "s1p", "wheeze") else f"{name} is {value:.0f}"
    return f"{name} ({kind.replace('_', ' ')})"


def why_now(contrib_row: pd.Series, feature_row: pd.Series, k: int = 3) -> list[str]:
    """Top-k reasons that raised the risk for one prediction."""
    top = contrib_row[contrib_row > 0].sort_values(ascending=False).head(k)
    return [describe(f, float(feature_row[f])) for f in top.index]
