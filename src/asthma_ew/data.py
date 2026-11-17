"""Step 1a: load AAMOS-00 and put watch data on a regular 1-minute grid.

AAMOS-00 stores time as `date` (study day 0..184) plus a clock time or hour.
We convert every timestamp to `t`, the number of minutes since the start of
study day 0, so all sources line up on one clock.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

MIN_PER_DAY = 1440

# Activity codes from the AAMOS-00 data dictionary (Mi Band 3).
ACTIVITY_GROUPS = {
    "walk": {1, 16, 33},
    "not_worn": {3},
    "charging": {6},
    "sedentary": {80, 89, 90, 91, 92, 96},
    "running": {66, 82, 98},
    "activity_high": {17},
    "sleep": {106, 112, 121, 122, 123},
}
CODE_TO_GROUP = {code: g for g, codes in ACTIVITY_GROUPS.items() for code in codes}

FILES = {
    "patient": "anonym_aamos00_patient_info.csv",
    "inhaler": "anonym_aamos00_smartinhaler.csv",
    "peakflow": "anonym_aamos00_peakflow.csv",
    "daily": "anonym_aamos00_dailyquestionnaire.csv",
    "weekly": "anonym_aamos00_weeklyquestionnaire.csv",
    "environment": "anonym_aamos00_environment.csv",
}
WATCH_FILES = [f"anonym_aamos00_smartwatch{i}.csv" for i in (1, 2, 3)]


def _read(raw_dir: Path, name: str) -> pd.DataFrame:
    df = pd.read_csv(raw_dir / name, na_values=["NA"])
    df["user_key"] = df["user_key"].astype(int)
    return df


def load_tables(raw_dir: str | Path) -> dict[str, pd.DataFrame]:
    """Load every non-watch AAMOS-00 table into a dict of DataFrames."""
    raw_dir = Path(raw_dir)
    return {key: _read(raw_dir, name) for key, name in FILES.items() if (raw_dir / name).exists()}


def load_watch(raw_dir: str | Path) -> pd.DataFrame:
    """Load the three smartwatch files and add `t` (minutes since day 0)."""
    raw_dir = Path(raw_dir)
    parts = [_read(raw_dir, f) for f in WATCH_FILES if (raw_dir / f).exists()]
    if not parts:
        raise FileNotFoundError(f"No smartwatch files found in {raw_dir}. See data/README.md.")
    w = pd.concat(parts, ignore_index=True)
    hhmm = w["time"].str.slice(0, 5).str.split(":", expand=True).astype(int)
    w["t"] = w["date"].astype(int) * MIN_PER_DAY + hhmm[0] * 60 + hhmm[1]
    w = w.drop_duplicates(["user_key", "t"]).sort_values(["user_key", "t"])
    return w[["user_key", "t", "activity_type", "intensity", "steps", "hr"]].reset_index(drop=True)


def minute_grid(watch_user: pd.DataFrame) -> pd.DataFrame:
    """Reindex one user's watch data onto a gap-free 1-minute grid.

    Adds:
      activity  - activity group name ("missing" where the watch sent nothing)
      q_hr      - heart-rate quality score 0..1 (0 when not worn, charging,
                  missing or physiologically implausible)
      is_night  - 1 between 23:00 and 06:59
    """
    t = np.arange(watch_user["t"].min(), watch_user["t"].max() + 1)
    g = watch_user.set_index("t").reindex(t)
    g.index.name = "t"
    g = g.reset_index()
    g["user_key"] = int(watch_user["user_key"].iloc[0])
    g["activity"] = g["activity_type"].map(CODE_TO_GROUP).fillna("other")
    g.loc[g["activity_type"].isna(), "activity"] = "missing"
    g["steps"] = g["steps"].fillna(0)

    hr = g["hr"]
    bad = hr.isna() | (hr < 30) | (hr > 220) | g["activity"].isin(["not_worn", "charging", "missing"])
    g["q_hr"] = np.where(bad, 0.0, 1.0)
    g.loc[bad, "hr"] = np.nan

    minute_of_day = g["t"] % MIN_PER_DAY
    g["day"] = g["t"] // MIN_PER_DAY
    g["is_night"] = ((minute_of_day >= 23 * 60) | (minute_of_day < 7 * 60)).astype(int)
    return g[["user_key", "t", "day", "is_night", "activity", "steps", "hr", "q_hr"]]
