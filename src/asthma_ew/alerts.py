"""Step 7: alert logic.

User alert
  fires when the attack probability crosses the user threshold, then stays
  quiet for a 30-min cooldown UNLESS the risk rises by a clear step (the
  attack may be getting worse).

EMS / caregiver alert (opt-in only)
  considered only when P(severe) crosses the EMS threshold. The user gets a
  countdown (default 45 s) to cancel; if they don't respond, the opted-in
  contacts are notified automatically.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


def user_alerts(t: np.ndarray, p: np.ndarray, threshold: float, cooldown_min: float, escalate_step: float = 0.15) -> np.ndarray:
    """Return the minutes at which a user alert is sent."""
    t, p = np.asarray(t, dtype=float), np.asarray(p, dtype=float)
    above = p >= threshold
    t, p = t[above], p[above]
    order = np.argsort(t)
    t, p = t[order], p[order]
    sent, last_t, last_p = [], -np.inf, 0.0
    for ti, pi in zip(t, p):
        if ti - last_t >= cooldown_min or pi >= last_p + escalate_step:
            sent.append(ti)
            last_t, last_p = ti, pi
    return np.array(sent, dtype=float)


@dataclass
class EmsDecision:
    action: str   # "none", "start_countdown", "send", "cancelled", "not_opted_in"
    reason: str


def ems_decision(p_severe: float, threshold: float, opted_in: bool, countdown_elapsed: bool = False,
                 user_cancelled: bool = False) -> EmsDecision:
    """Decide what the EMS / caregiver path does at one moment."""
    if p_severe < threshold:
        return EmsDecision("none", "severe risk below threshold")
    if not opted_in:
        return EmsDecision("not_opted_in", "user has not added emergency contacts")
    if user_cancelled:
        return EmsDecision("cancelled", "user cancelled during the countdown")
    if not countdown_elapsed:
        return EmsDecision("start_countdown", "severe risk high; giving the user time to cancel")
    return EmsDecision("send", "no response before the countdown ended")
