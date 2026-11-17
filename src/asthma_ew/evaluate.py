"""Step 9: how we judge the model.

Accuracy is meaningless here (a model that never predicts an attack is ~99%
"accurate"), so we report:

  AUROC / AUPRC        how well risk scores rank attack minutes above quiet ones
  event sensitivity    share of attacks with at least one alert in the window
                       before onset (event-level: matches what a user experiences)
  lead time            how long before onset the first alert came
  false alarms / day   alerts not followed by an attack within the window

All numbers come from leave-one-person-out testing: each person is tested by
a model that never saw their data.
"""

from __future__ import annotations

import numpy as np
from sklearn.metrics import average_precision_score, roc_auc_score

from .alerts import user_alerts


def threshold_for_sensitivity(p: np.ndarray, y: np.ndarray, target: float) -> float:
    """Highest threshold that still flags `target` share of positive minutes."""
    pos = np.asarray(p)[np.asarray(y) == 1]
    if len(pos) == 0:
        return 0.5
    return float(np.quantile(pos, 1 - target))


def threshold_for_event_sensitivity(people: list[tuple[np.ndarray, np.ndarray, np.ndarray]], window: float,
                                    cooldown: float, step_min: float, target: float) -> float:
    """Highest alert threshold that still catches `target` share of attacks.

    `people` holds (t, p, onsets) for each calibration person. Event-level:
    an attack counts as caught if any alert fired in the window before onset.
    Higher thresholds mean fewer false alarms, so we search for the highest
    one that meets the sensitivity target (binary search over candidates).
    """
    all_p = np.concatenate([p for _, p, _ in people]) if people else np.array([0.5])
    total = sum(len(o) for _, _, o in people)
    if total == 0:
        return float(np.quantile(all_p, 0.99))
    cands = np.unique(np.quantile(all_p, np.linspace(0.0, 0.9995, 200)))

    def sens(th):
        caught = sum(event_metrics(t, p, th, o, window, cooldown, step_min)["n_caught"] for t, p, o in people)
        return caught / total

    lo, hi, best = 0, len(cands) - 1, float(cands[0])
    while lo <= hi:
        mid = (lo + hi) // 2
        if sens(cands[mid]) >= target:
            best, lo = float(cands[mid]), mid + 1
        else:
            hi = mid - 1
    return best


def minute_metrics(y: np.ndarray, p: np.ndarray) -> dict:
    y = np.asarray(y)
    if y.min() == y.max():
        return {"auroc": np.nan, "auprc": np.nan, "prevalence": float(y.mean())}
    return {
        "auroc": float(roc_auc_score(y, p)),
        "auprc": float(average_precision_score(y, p)),
        "prevalence": float(y.mean()),
    }


def event_metrics(t: np.ndarray, p: np.ndarray, threshold: float, onsets: np.ndarray, window: float,
                  cooldown: float, step_min: float) -> dict:
    """Event-level results for one person and one window."""
    alerts = user_alerts(t, p, threshold, cooldown)
    caught, leads = [], []
    for o in onsets:
        hits = alerts[(alerts >= o - window) & (alerts < o)]
        caught.append(len(hits) > 0)
        if len(hits):
            leads.append(float(o - hits.min()))
    false = int(sum(not np.any((onsets > a) & (onsets <= a + window)) for a in alerts))
    days = len(t) * step_min / 1440
    return {"n_episodes": len(onsets), "n_caught": int(sum(caught)), "caught": caught, "leads": leads,
            "n_alerts": len(alerts), "n_false": false, "days": days}


def sensitivity_at_budget(people: list[tuple[np.ndarray, np.ndarray, np.ndarray]], window: float,
                          cooldown: float, step_min: float, budget_per_day: float) -> dict:
    """Best event sensitivity whose false-alarm rate stays within `budget_per_day`.

    One threshold shared by everyone, swept over 200 candidates: this traces the
    trade-off curve (like an ROC curve) rather than tuning a deployable threshold.
    """
    all_p = np.concatenate([p for _, p, _ in people])
    cands = np.unique(np.quantile(all_p, np.linspace(0.5, 0.99999, 200)))
    best = {"threshold": np.nan, "event_sensitivity": 0.0, "false_alarms_per_day": 0.0, "median_lead_min": np.nan}
    for th in cands:
        tot = caught = false = 0
        days = 0.0
        leads = []
        for t, p, o in people:
            em = event_metrics(t, p, th, o, window, cooldown, step_min)
            tot += em["n_episodes"]; caught += em["n_caught"]; false += em["n_false"]; days += em["days"]
            leads += em["leads"]
        fa = false / days if days else np.nan
        sens = caught / tot if tot else np.nan
        if fa <= budget_per_day and sens > best["event_sensitivity"]:
            best = {"threshold": float(th), "event_sensitivity": float(sens), "false_alarms_per_day": float(fa),
                    "median_lead_min": float(np.median(leads)) if leads else np.nan}
    return best
