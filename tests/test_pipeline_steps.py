"""Grid, synthetic signals, baselines, features, targets: shape and no look-ahead."""

import numpy as np

from asthma_ew import baseline, dataset, features, synthetic
from asthma_ew.data import minute_grid


def _build(cfg, watch_user, episodes, seed=1):
    g = minute_grid(watch_user)
    g, prof = synthetic.generate(g, episodes, cfg, np.random.default_rng(seed))
    b = baseline.compute(g, episodes, cfg["features"]["signals"], cfg)
    return g, b, features.build(g, b, cfg)


def test_quality_is_zero_when_watch_not_worn(watch_user):
    g = minute_grid(watch_user)
    assert (g.loc[g["t"].between(1000, 1059), "q_hr"] == 0).all()
    assert g.loc[g["t"].between(1000, 1059), "hr"].isna().all()


def test_histamine_rises_before_onset(cfg, watch_user, episodes):
    g = minute_grid(watch_user)
    g, prof = synthetic.generate(g, episodes, cfg, np.random.default_rng(3))
    onset = episodes["onset_t"].iloc[0]
    before = g.loc[g["t"].between(onset - 600, onset - 400), "histamine"].mean()
    near = g.loc[g["t"].between(onset - 20, onset + 20), "histamine"].max()
    # early responses spike right before onset; late responses spiked hours earlier
    window = g.loc[g["t"].between(onset - 8 * 60, onset), "histamine"].max()
    assert max(near, window) > before * 1.5


def test_baseline_uses_only_past_days(cfg, watch_user, episodes):
    g, b, _ = _build(cfg, watch_user, episodes)
    # day 0 has no past data -> pure population prior (personal weight 0)
    assert b.loc[b["day"] == 0, "hr_base_w"].max() == 0
    # later days blend in personal data
    assert b.loc[b["day"] == 10, "hr_base_w"].max() > 0


def test_features_have_no_look_ahead(cfg, watch_user, episodes):
    """Changing the future must not change features at an earlier minute."""
    g, b, f1 = _build(cfg, watch_user, episodes)
    g2 = g.copy()
    cut = 12 * 1440
    g2.loc[g2["t"] > cut, ["hr", "rr", "histamine", "s1p", "wheeze"]] *= 3
    f2 = features.build(g2, b, cfg)
    cols = [c for c in f1.columns if c not in ("user_key", "t")]
    a = f1.loc[f1["t"] <= cut, cols].to_numpy()
    c = f2.loc[f2["t"] <= cut, cols].to_numpy()
    assert np.allclose(a, c, equal_nan=True)


def test_targets_and_exclusion(cfg, watch_user, episodes):
    _, _, f = _build(cfg, watch_user, episodes)
    rows = dataset.add_targets(f, episodes, cfg)
    onset = episodes["onset_t"].iloc[0]
    r = rows.set_index("t")
    assert r.loc[onset - 10, "y_15"] == 1 and r.loc[onset - 10, "sev_moderate"] == 1
    assert r.loc[onset - 30, "y_15"] == 0 and r.loc[onset - 30, "y_60"] == 1
    assert onset + 10 not in r.index          # minutes during an attack are dropped
    sev_onset = episodes["onset_t"].iloc[1]
    assert r.loc[sev_onset - 5, "sev_severe"] == 1
