"""Run the whole pipeline: build data, train and test, write a report.

Usage:
    python scripts/run_pipeline.py                      # all people
    python scripts/run_pipeline.py --users 113 190 217  # quick run on a few people
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from asthma_ew.config import load_config  # noqa: E402
from asthma_ew.pipeline import prepare, run_lopo, summarize  # noqa: E402


def op_table(points: list[dict]) -> str:
    if not points:
        return ""
    out = "| window_min | model | alarms/day budget | event_sensitivity | false_alarms_per_day | median_lead_min |\n"
    out += "|---|---|---|---|---|---|\n"
    for r in points:
        lead = "-" if pd.isna(r["median_lead_min"]) else f"{r['median_lead_min']:.0f}"
        out += (f"| {r['window_min']} | {r['model']} | {r['budget_per_day']} | {r['event_sensitivity']:.2f} | "
                f"{r['false_alarms_per_day']:.2f} | {lead} |\n")
    return out


def write_report(summary: dict, path: Path) -> None:
    lik = pd.DataFrame(summary["likelihood"])
    fmt = lik.copy()
    for c in ["auroc", "auprc", "prevalence", "event_sensitivity", "allergy_event_sensitivity"]:
        fmt[c] = fmt[c].map(lambda v: "-" if pd.isna(v) else f"{v:.2f}")
    fmt["median_lead_min"] = fmt["median_lead_min"].map(lambda v: "-" if pd.isna(v) else f"{v:.0f}")
    fmt["false_alarms_per_day"] = fmt["false_alarms_per_day"].map(lambda v: "-" if pd.isna(v) else f"{v:.2f}")
    cols = ["window_min", "model", "auroc", "auprc", "event_sensitivity", "allergy_event_sensitivity",
            "median_lead_min", "false_alarms_per_day"]
    header = "| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
    table = header + "".join("| " + " | ".join(str(r[c]) for c in cols) + " |\n" for _, r in fmt.iterrows())
    sev = summary["severity"]
    au = [a for a in summary["per_user_auroc_60"] if not pd.isna(a)]
    ex = summary["example_explanation"]
    lines = [
        "# Results (leave-one-person-out, semi-synthetic data)\n",
        f"{summary['n_users']} people, {summary['n_episodes']} attack episodes. Biomarker, RR and wheeze "
        "signals are synthetic; HR, activity and attack timing are real (AAMOS-00). These numbers test the "
        "pipeline and the design, not clinical performance.\n",
        "## Attack likelihood\n", table,
        "\n## Same models at a fixed false-alarm budget\n",
        "Each row uses the one shared threshold that catches the most attacks while staying within the "
        "budget. This traces the trade-off curve; it is not a threshold tuned for deployment.\n\n",
        op_table(summary.get("operating_points", [])),
        "\n## Severity (minutes before an attack)\n",
        f"- At least moderate: AUROC {sev['sev_moderate']['auroc']:.2f}\n",
        f"- Severe: AUROC {sev['sev_severe']['auroc']:.2f}\n",
        f"\nPer-person AUROC (60-min window): mean {np.mean(au):.2f}, SD {np.std(au):.2f}, "
        f"range {np.min(au):.2f}-{np.max(au):.2f}\n",
    ]
    if ex:
        lines += ["\n## Example \"Why now?\" explanation\n",
                  f"{ex['minutes_before_onset']:.0f} min before an attack, P(attack within 60 min) = {ex['p_y_60']:.2f}. Reasons:\n"]
        lines += [f"- {r}\n" for r in ex["reasons"]]
    path.write_text("".join(lines), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", default=None)
    ap.add_argument("--users", type=int, nargs="*", default=None)
    args = ap.parse_args()

    cfg = load_config(args.config)
    root = Path(__file__).resolve().parents[1]
    out_dir = root / cfg["data"]["out_dir"]
    out_dir.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    print("Building data (labels, synthetic signals, baselines, features)...")
    data = prepare(cfg, str(root / cfg["data"]["raw_dir"]), users=args.users)
    print(f"Leave-one-person-out training on {len(data)} people...")
    res = run_lopo(cfg, data)
    summary = summarize(cfg, data, res)

    res["predictions"].to_csv(out_dir / "predictions.csv.gz", index=False)
    pd.concat([d.episodes for d in data.values()]).to_csv(out_dir / "episodes.csv", index=False)
    with open(out_dir / "metrics.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, default=float)
    write_report(summary, out_dir / "report.md")
    print((out_dir / "report.md").read_text(encoding="utf-8"))
    print(f"Done in {time.time() - t0:.0f} s. Outputs in {out_dir}/")


if __name__ == "__main__":
    main()
