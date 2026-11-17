"""The ATS/ERS label rules, checked on hand-made examples."""

import pandas as pd

from asthma_ew.labels import build_episodes, daily_evidence


def _tables(inhaler_rows, pef_rows, daily_rows, weekly_rows):
    patient = pd.DataFrame({"user_key": [1], "pef_best": [500], "max_pef_expected": [480],
                            "inhaler_start_date": [0], "inhaler_end_date": [30]})
    return {
        "patient": patient,
        "inhaler": pd.DataFrame(inhaler_rows, columns=["user_key", "date", "hour"]),
        "peakflow": pd.DataFrame(pef_rows, columns=["user_key", "date", "hour", "pef_max"]),
        "daily": pd.DataFrame(daily_rows, columns=["user_key", "date", "daily_night_symp", "daily_day_symp",
                                                   "daily_prev_inhaler", "daily_relief_inhaler"]),
        "weekly": pd.DataFrame(weekly_rows, columns=["user_key", "date", "weekly_er", "weekly_hospital", "weekly_oral"]),
    }


def test_low_peak_flow_makes_moderate_and_earliest_event_sets_onset(cfg):
    # puff at 14:00, peak flow at 70% of personal best at 15:00, same day
    t = _tables([(1, 20, 14)], [(1, 20, 15, 350)], [(1, 20, "TRUE", "FALSE", "2", "1")], [])
    ev = daily_evidence(t, cfg)
    day = ev[ev["date"] == 20].iloc[0]
    assert day["severity"] == 2          # moderate, not mild
    assert day["onset_hour"] == 14       # the earlier event (the puff)


def test_symptoms_plus_rescue_is_mild(cfg):
    t = _tables([(1, 20, 9)], [], [(1, 20, "TRUE", "FALSE", "2", "1")], [])
    ev = daily_evidence(t, cfg)
    assert ev[ev["date"] == 20].iloc[0]["severity"] == 1


def test_er_visit_days_ago_is_severe_on_the_right_day(cfg):
    t = _tables([], [], [], [(1, 21, "-3", "0", "1")])  # weekly survey on day 21: ER visit 3 days ago
    ev = daily_evidence(t, cfg)
    assert ev[ev["date"] == 18].iloc[0]["severity"] == 3


def test_increased_inhaler_use_is_personal(cfg):
    # usual = 4 puffs/day; 6 puffs is not "increased" (needs > max(8, 6)), 9 puffs is
    rows = [(1, d, 10) for d in range(0, 14) for _ in range(4)]
    rows += [(1, 14, 10)] * 6 + [(1, 15, 10)] * 9
    ev = daily_evidence(_tables(rows, [], [], []), cfg)
    assert ev[ev["date"] == 14].iloc[0]["inhaler_increase"] == 0
    assert ev[ev["date"] == 15].iloc[0]["inhaler_increase"] == 1


def test_neighbouring_days_merge_and_most_severe_wins(cfg):
    ev = pd.DataFrame({"user_key": [1, 1, 1], "date": [5, 6, 20], "severity": [1, 3, 2],
                       "onset_hour": [8, 12, 9], "onset_precision": ["hour", "day", "hour"]})
    ep = build_episodes(ev, cfg)
    assert len(ep) == 2
    assert ep.iloc[0]["severity"] == 3 and ep.iloc[0]["onset_t"] == 5 * 1440 + 8 * 60
