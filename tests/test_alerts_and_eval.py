"""Alert logic, metrics and the comparison rule."""

import numpy as np

from asthma_ew.alerts import ems_decision, user_alerts
from asthma_ew.evaluate import event_metrics, threshold_for_event_sensitivity


def test_cooldown_blocks_repeats_unless_risk_rises():
    t = np.arange(0, 60, 5, dtype=float)
    p = np.array([0.6] * 6 + [0.9] + [0.6] * 5)
    sent = user_alerts(t, p, threshold=0.5, cooldown_min=30)
    assert list(sent) == [0.0, 30.0]          # 30 min cooldown, and the jump to 0.9 is at t=30 anyway
    p2 = np.array([0.6, 0.6, 0.9] + [0.6] * 9)
    sent2 = user_alerts(t, p2, threshold=0.5, cooldown_min=30)
    assert 10.0 in sent2                       # risk rose a clear step -> alert despite cooldown


def test_ems_needs_opt_in_and_countdown():
    assert ems_decision(0.2, 0.5, opted_in=True).action == "none"
    assert ems_decision(0.9, 0.5, opted_in=False).action == "not_opted_in"
    assert ems_decision(0.9, 0.5, opted_in=True).action == "start_countdown"
    assert ems_decision(0.9, 0.5, opted_in=True, countdown_elapsed=True, user_cancelled=True).action == "cancelled"
    assert ems_decision(0.9, 0.5, opted_in=True, countdown_elapsed=True).action == "send"


def test_event_metrics_counts_caught_and_false_alarms():
    t = np.arange(0, 2000, 5, dtype=float)
    p = np.zeros_like(t)
    p[(t >= 950) & (t < 1000)] = 0.9   # alert before the attack at 1000
    p[(t >= 1500) & (t < 1510)] = 0.9  # alert with no attack after it
    em = event_metrics(t, p, 0.5, np.array([1000.0]), window=60, cooldown=30, step_min=5)
    assert em["n_caught"] == 1 and em["n_false"] == 1 and em["leads"] == [50.0]


def test_threshold_search_meets_target():
    t = np.arange(0, 3000, 5, dtype=float)
    rng = np.random.default_rng(0)
    p = rng.random(len(t)) * 0.3
    onsets = np.array([1000.0, 2000.0])
    for o in onsets:
        p[(t >= o - 30) & (t < o)] = 0.8
    th = threshold_for_event_sensitivity([(t, p, onsets)], window=60, cooldown=30, step_min=5, target=1.0)
    assert 0.3 <= th <= 0.8
