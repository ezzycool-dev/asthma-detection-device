"""Glue code: run every step for every person, then leave-one-person-out testing."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from . import baseline, dataset, features, labels, synthetic
from .data import load_tables, load_watch, minute_grid
from .evaluate import event_metrics, minute_metrics, sensitivity_at_budget, threshold_for_event_sensitivity
from .explain import why_now
from .models import LIKELIHOOD_HEADS, SEVERITY_HEADS, TreeModel
from .rules import RULE_THRESHOLD, two_of_three_score


@dataclass
class UserData:
    user_key: int
    train: pd.DataFrame
    test: pd.DataFrame
    episodes: pd.DataFrame
    profile: dict = field(default_factory=dict)


def prepare(cfg: dict, raw_dir: str, users: list[int] | None = None, log=print) -> dict[int, UserData]:
    """Steps 1-5 for every person with watch data."""
    tables = load_tables(raw_dir)
    watch = load_watch(raw_dir)
    evidence = labels.daily_evidence(tables, cfg)
    episodes = labels.build_episodes(evidence, cfg)
    allergic = labels.allergy_days(tables["daily"]) if "daily" in tables else set()
    episodes["allergy_trigger"] = [(u, d) in allergic for u, d in zip(episodes["user_key"], episodes["start_day"])]
    patients = tables["patient"].set_index("user_key")

    out = {}
    for uid in sorted(watch["user_key"].unique()):
        if users and uid not in users:
            continue
        rng = np.random.default_rng([cfg["seed"], int(uid)])
        grid = minute_grid(watch[watch["user_key"] == uid])
        eps = episodes[(episodes["user_key"] == uid) & (episodes["onset_t"].between(grid["t"].min(), grid["t"].max()))]
        grid, prof = synthetic.generate(grid, eps, cfg, rng)
        base = baseline.compute(grid, eps, cfg["features"]["signals"], cfg)
        prof_feats = features.profile_features(patients.loc[uid]) if uid in patients.index else {}
        feats = features.build(grid, base, cfg, prof_feats)
        rows = dataset.add_targets(feats, eps, cfg)
        out[uid] = UserData(uid, dataset.sample(rows, cfg, True), dataset.sample(rows, cfg, False), eps, prof)
        log(f"  user {uid}: {len(eps)} episodes, {len(out[uid].train):,} train rows")
    return out


def _thresholds(model: TreeModel, data: dict, calib_users: list, heads: list[str], cfg: dict) -> dict:
    """Alert threshold per window, tuned on calibration people (never the test person)."""
    step = cfg["targets"]["quiet_subsample_every"]
    out = {}
    preds = {v: model.predict(data[v].test) for v in calib_users}
    for h in heads:
        people = [(data[v].test["t"].to_numpy(float), preds[v][f"p_{h}"].to_numpy(),
                   data[v].episodes["onset_t"].to_numpy(float)) for v in calib_users]
        out[h] = threshold_for_event_sensitivity(people, int(h.split("_")[1]), cfg["alerts"]["cooldown_min"],
                                                 step, cfg["alerts"]["sensitivity_target"])
    return out


def run_lopo(cfg: dict, data: dict[int, UserData], log=print) -> dict:
    """Leave-one-person-out: train on everyone else, test on the person left out."""
    users = sorted(data)
    feat_all = features.feature_columns(data[users[0]].train)
    feat_hr = features.feature_columns(data[users[0]].train, only="hr")
    rng = np.random.default_rng(cfg["seed"])
    preds, fold_info, example = [], [], None

    for i, u in enumerate(users, 1):
        others = [v for v in users if v != u]
        calib_users = list(rng.choice(others, size=max(2, len(others) // 5), replace=False))
        fit_users = [v for v in others if v not in calib_users]  # tuning never touches the test person
        train = pd.concat([data[v].train for v in fit_users], ignore_index=True)
        test = data[u].test

        full = TreeModel(cfg, feat_all).fit(train)
        hr_only = TreeModel(cfg, feat_hr, heads=LIKELIHOOD_HEADS).fit(train)
        thr_full = _thresholds(full, data, calib_users, LIKELIHOOD_HEADS, cfg)
        thr_hr = _thresholds(hr_only, data, calib_users, LIKELIHOOD_HEADS, cfg)

        p = test[["user_key", "t", *LIKELIHOOD_HEADS, *SEVERITY_HEADS]].copy()
        p = p.join(full.predict(test))
        p = p.join(hr_only.predict(test).add_prefix("hr_"))
        p["rule"] = two_of_three_score(test, cfg["features"]["signals"])
        preds.append(p)
        fold_info.append({"user": u, "thr_full": thr_full, "thr_hr": thr_hr})

        if example is None and test["y_60"].sum() > 0:
            j = p.loc[test["y_60"] == 1, "p_y_60"].idxmax()
            contrib = full.contributions(test.loc[[j]], "y_60").iloc[0]
            example = {"user": int(u), "minutes_before_onset": float(test.loc[j, "time_to_onset"]),
                       "p_y_60": float(p.loc[j, "p_y_60"]), "reasons": why_now(contrib, test.loc[j])}
        log(f"  fold {i}/{len(users)} (test user {u}) done")

    return {"predictions": pd.concat(preds, ignore_index=True), "folds": fold_info, "example": example}


def summarize(cfg: dict, data: dict[int, UserData], res: dict) -> dict:
    """Pooled metrics for the full model, HR-only model and 2-of-3 rule."""
    pred = res["predictions"]
    step = cfg["targets"]["quiet_subsample_every"]
    cooldown = cfg["alerts"]["cooldown_min"]
    thr = {f["user"]: f for f in res["folds"]}
    rows = []
    for h in LIKELIHOOD_HEADS:
        window = int(h.split("_")[1])
        for name, col, thr_key in [("Full model", f"p_{h}", "thr_full"), ("HR-only model", f"hr_p_{h}", "thr_hr"),
                                   ("2-of-3 rule", "rule", None)]:
            mm = minute_metrics(pred[h], pred[col])
            caught = leads = 0
            tot = alerts = false = days = 0
            allergy_tot = allergy_caught = 0
            lead_list = []
            for u, d in data.items():
                pu = pred[pred["user_key"] == u]
                onsets = d.episodes["onset_t"].to_numpy(dtype=float)
                if len(pu) == 0:
                    continue
                th = RULE_THRESHOLD if thr_key is None else thr[u][thr_key][h]
                em = event_metrics(pu["t"].to_numpy(float), pu[col].to_numpy(), th, onsets, window, cooldown, step)
                tot += em["n_episodes"]; caught += em["n_caught"]; alerts += em["n_alerts"]
                false += em["n_false"]; days += em["days"]; lead_list += em["leads"]
                flags = d.episodes["allergy_trigger"].to_numpy()
                allergy_tot += int(flags.sum())
                allergy_caught += int(np.sum(np.array(em["caught"], dtype=bool) & flags)) if len(flags) else 0
            rows.append({
                "window_min": window, "model": name,
                "auroc": mm["auroc"], "auprc": mm["auprc"], "prevalence": mm["prevalence"],
                "event_sensitivity": caught / tot if tot else np.nan,
                "allergy_event_sensitivity": allergy_caught / allergy_tot if allergy_tot else np.nan,
                "median_lead_min": float(np.median(lead_list)) if lead_list else np.nan,
                "false_alarms_per_day": false / days if days else np.nan,
            })
    budgets = cfg["alerts"].get("false_alarm_budgets", [1, 3])
    op_points = []
    for h in LIKELIHOOD_HEADS:
        window = int(h.split("_")[1])
        for name, col in [("Full model", f"p_{h}"), ("HR-only model", f"hr_p_{h}"), ("2-of-3 rule", "rule")]:
            people = []
            for u, d in data.items():
                pu = pred[pred["user_key"] == u]
                if len(pu):
                    people.append((pu["t"].to_numpy(float), pu[col].to_numpy(),
                                   d.episodes["onset_t"].to_numpy(dtype=float)))
            for b in budgets:
                op = sensitivity_at_budget(people, window, cooldown, step, b)
                op_points.append({"window_min": window, "model": name, "budget_per_day": b, **op})
    sev = pred[pred["y_360"] == 1]
    severity = {h: minute_metrics(sev[h], sev[f"p_{h}"]) for h in SEVERITY_HEADS}
    per_user = []
    for u in data:
        pu = pred[pred["user_key"] == u]
        mm = minute_metrics(pu["y_60"], pu["p_y_60"])
        per_user.append(mm["auroc"])
    return {"likelihood": rows, "operating_points": op_points, "severity": severity, "per_user_auroc_60": per_user,
            "n_users": len(data), "n_episodes": int(sum(len(d.episodes) for d in data.values())),
            "example_explanation": res["example"]}
