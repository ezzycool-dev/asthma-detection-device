"""Shared fixtures: a tiny fake person so tests run without the real dataset."""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from asthma_ew.config import load_config  # noqa: E402


@pytest.fixture
def cfg():
    return load_config()


@pytest.fixture
def watch_user():
    """20 days of minute-level watch data for one fake person."""
    rng = np.random.default_rng(0)
    n = 20 * 1440
    t = np.arange(n)
    activity = np.where((t % 1440) < 7 * 60, 112, 80)  # asleep until 7 am, then sedentary
    activity[1000:1060] = 3                             # watch off for an hour
    return pd.DataFrame({
        "user_key": 1, "t": t, "activity_type": activity, "intensity": 0,
        "steps": rng.integers(0, 5, n), "hr": rng.normal(70, 5, n),
    })


@pytest.fixture
def episodes():
    """Two attacks: a moderate one on day 15 at 14:00 and a severe one on day 18 at 09:00."""
    return pd.DataFrame({
        "user_key": [1, 1], "start_day": [15, 18], "end_day": [15, 18],
        "onset_t": [15 * 1440 + 14 * 60, 18 * 1440 + 9 * 60], "severity": [2, 3],
        "onset_precision": ["hour", "hour"],
    })
