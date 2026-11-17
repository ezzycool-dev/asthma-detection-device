"""Step 1b: turn AAMOS-00 clinical events into attack episodes.

Severity follows the ATS/ERS 2009 Task Force definitions, translated into
AAMOS-00 columns:

  mild     - asthma symptoms (day or night) AND rescue inhaler used,
             with no change in treatment
  moderate - a temporary change in treatment: increased rescue inhaler use
             (personal rule: more than 2x the usual daily puffs and at least
             usual + 2), OR peak flow below 80% of personal best, OR more
             preventer inhaler than usual
  severe   - ER visit or hospital stay, OR more oral steroids than usual

One day can carry several pieces of evidence; the most severe one wins.
Neighbouring event days merge into one episode whose onset is the earliest
event (hour-level when an inhaler puff or peak-flow reading gives the hour).

Labels are only ever used as the training answer key, never as model inputs.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from .data import MIN_PER_DAY

SEVERITY = {"none": 0, "mild": 1, "moderate": 2, "severe": 3}
SEVERITY_NAME = {v: k for k, v in SEVERITY.items()}


def personal_best_pef(peakflow: pd.DataFrame, patient: pd.DataFrame) -> pd.Series:
    """Personal best peak flow per user.

    Reported personal best if known; otherwise the highest reading in the
    user's first 14 days; otherwise the predicted maximum from patient info.
    """
    pb = patient.set_index("user_key")["pef_best"].astype(float)
    pred = patient.set_index("user_key")["max_pef_expected"].astype(float)
    if len(peakflow):
        first = peakflow.groupby("user_key")["date"].transform("min")
        early = peakflow[peakflow["date"] < first + 14]
        early_max = early.groupby("user_key")["pef_max"].max()
        pb = pb.fillna(early_max)
    return pb.fillna(pred)


def _offsets(value) -> list[int]:
    """Parse weekly answers like '-3,-6' (days ago) into [-3, -6]; '0' means none."""
    if pd.isna(value):
        return []
    out = []
    for token in str(value).replace('"', "").split(","):
        token = token.strip()
        if token and token.lstrip("-").isdigit() and int(token) < 0:
            out.append(int(token))
    return out


def daily_evidence(tables: dict[str, pd.DataFrame], cfg: dict) -> pd.DataFrame:
    """One row per user-day with every piece of evidence and the day's severity."""
    lab = cfg["labels"]
    patient = tables["patient"]
    inhaler = tables.get("inhaler", pd.DataFrame(columns=["user_key", "date", "hour"]))
    peak = tables.get("peakflow", pd.DataFrame(columns=["user_key", "date", "hour", "pef_max"]))
    daily = tables.get("daily", pd.DataFrame(columns=["user_key", "date"]))
    weekly = tables.get("weekly", pd.DataFrame(columns=["user_key", "date"]))

    # --- rescue inhaler: puffs per day and the hour of the first puff
    puffs = inhaler.groupby(["user_key", "date"]).agg(puffs=("hour", "size"), first_puff_hour=("hour", "min"))
    rows = []
    for uid, p in patient.set_index("user_key").iterrows():
        start, end = p.get("inhaler_start_date"), p.get("inhaler_end_date")
        if pd.isna(start) or pd.isna(end):
            continue
        days = np.arange(int(start), int(end) + 1)
        rows.append(pd.DataFrame({"user_key": uid, "date": days}))
    monitored = pd.concat(rows, ignore_index=True) if rows else pd.DataFrame(columns=["user_key", "date"])
    inh = monitored.merge(puffs.reset_index(), on=["user_key", "date"], how="left")
    inh["puffs"] = inh["puffs"].fillna(0)
    # usual daily puffs = median of the previous 14 days (past only)
    inh = inh.sort_values(["user_key", "date"])
    inh["usual_puffs"] = inh.groupby("user_key")["puffs"].transform(
        lambda s: s.shift(1).rolling(lab["usual_window_days"], min_periods=3).median()
    )
    limit = np.maximum(lab["inhaler_increase_factor"] * inh["usual_puffs"], inh["usual_puffs"] + lab["inhaler_increase_floor"])
    inh["inhaler_increase"] = (inh["usual_puffs"].notna() & (inh["puffs"] > limit)).astype(int)

    # --- peak flow below 80% of personal best
    pb = personal_best_pef(peak, patient)
    pk = peak.copy()
    pk["pct_best"] = 100 * pk["pef_max"] / pk["user_key"].map(pb)
    low = pk[pk["pct_best"] < lab["pef_moderate_pct"]]
    pef_low = low.groupby(["user_key", "date"]).agg(first_low_pef_hour=("hour", "min"), min_pct_best=("pct_best", "min"))

    # --- daily questionnaire
    dq = daily.copy()
    for c in ["daily_night_symp", "daily_day_symp"]:
        dq[c] = dq[c].astype(str).str.upper().eq("TRUE")
    dq["symptoms"] = (dq["daily_night_symp"] | dq["daily_day_symp"]).astype(int)
    dq["relief_reported"] = (pd.to_numeric(dq["daily_relief_inhaler"], errors="coerce").fillna(0) > 0).astype(int)
    dq["preventer_more"] = (pd.to_numeric(dq["daily_prev_inhaler"], errors="coerce") == 4).astype(int)
    dq = dq.groupby(["user_key", "date"])[["symptoms", "relief_reported", "preventer_more"]].max()

    # --- weekly questionnaire: ER / hospital give the exact day ("days ago");
    #     extra oral steroids only give the week, so we place it mid-week (-3 days)
    sev = []
    for _, r in weekly.iterrows():
        for col in ["weekly_er", "weekly_hospital"]:
            for off in _offsets(r.get(col)):
                sev.append((int(r["user_key"]), int(r["date"]) + off, "day"))
        if pd.to_numeric(r.get("weekly_oral"), errors="coerce") == 3:
            sev.append((int(r["user_key"]), int(r["date"]) - 3, "week"))
    severe = pd.DataFrame(sev, columns=["user_key", "date", "severe_precision"])
    severe = severe.drop_duplicates(["user_key", "date"]).set_index(["user_key", "date"])
    severe["severe"] = 1

    # --- combine on user-day
    keys = pd.concat(
        [inh[["user_key", "date"]], dq.reset_index()[["user_key", "date"]], pef_low.reset_index()[["user_key", "date"]], severe.reset_index()[["user_key", "date"]]]
    ).drop_duplicates()
    ev = keys.merge(inh, on=["user_key", "date"], how="left")
    for part in (dq, pef_low, severe):
        ev = ev.merge(part.reset_index(), on=["user_key", "date"], how="left")
    for c in ["puffs", "inhaler_increase", "symptoms", "relief_reported", "preventer_more", "severe"]:
        ev[c] = ev[c].fillna(0).astype(int)
    ev["low_pef"] = ev["first_low_pef_hour"].notna().astype(int)

    used_rescue = (ev["puffs"] > 0) | (ev["relief_reported"] > 0)
    moderate = (ev["inhaler_increase"] + ev["low_pef"] + ev["preventer_more"]) > 0
    mild = (ev["symptoms"] > 0) & used_rescue
    ev["severity"] = np.select([ev["severe"] > 0, moderate, mild], [3, 2, 1], default=0)

    hours = ev[["first_puff_hour", "first_low_pef_hour"]].min(axis=1)
    ev["onset_hour"] = hours.fillna(lab["default_onset_hour"]).astype(int)
    ev["onset_precision"] = np.where(hours.notna(), "hour", "day")
    return ev.sort_values(["user_key", "date"]).reset_index(drop=True)


ALLERGEN_TRIGGERS = {"5", "6", "7", "8", "9"}  # mould, dust mites, feathers, animals, pollen


def allergy_days(daily: pd.DataFrame) -> set[tuple[int, int]]:
    """(user_key, date) pairs where the daily survey lists an allergy trigger."""
    out = set()
    for _, r in daily.iterrows():
        codes = set(str(r.get("daily_triggers", "")).replace('"', "").replace(" ", "").split(","))
        if codes & ALLERGEN_TRIGGERS:
            out.add((int(r["user_key"]), int(r["date"])))
    return out


def build_episodes(evidence: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Merge neighbouring event days into episodes.

    Returns one row per episode: user_key, start_day, end_day, onset_t
    (minutes since day 0), severity (1-3), onset_precision.
    """
    gap = cfg["labels"]["merge_gap_days"]
    ev = evidence[evidence["severity"] > 0].sort_values(["user_key", "date"])
    out = []
    for uid, g in ev.groupby("user_key"):
        new_episode = g["date"].diff().fillna(gap + 2) > gap + 1
        episode_id = new_episode.cumsum()
        for _, e in g.groupby(episode_id):
            first = e.iloc[0]
            out.append(
                {
                    "user_key": uid,
                    "start_day": int(first["date"]),
                    "end_day": int(e["date"].max()),
                    "onset_t": int(first["date"]) * MIN_PER_DAY + int(first["onset_hour"]) * 60,
                    "severity": int(e["severity"].max()),
                    "onset_precision": first["onset_precision"],
                }
            )
    cols = ["user_key", "start_day", "end_day", "onset_t", "severity", "onset_precision"]
    return pd.DataFrame(out, columns=cols)
