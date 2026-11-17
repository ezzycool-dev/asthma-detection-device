"""Step 6: the prediction models.

TreeModel trains one gradient-boosted tree classifier (LightGBM) per output:

  y_15, y_60, y_360        attack likelihood within 15 / 60 / 360 min
  sev_moderate, sev_severe stacked severity of the coming attack

Severity heads are trained only on minutes that come before an attack
(y_360 = 1), since severity only matters when an attack is coming.

Class imbalance: attack minutes are rare, so each classifier weights the
positive class by (negatives / positives). Extra medical caution is applied
later through alert thresholds, not here.

A two-branch GRU (see gru.py) is the planned next model; it must beat these
trees to be used.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
from lightgbm import LGBMClassifier

LIKELIHOOD_HEADS = ["y_15", "y_60", "y_360"]
SEVERITY_HEADS = ["sev_moderate", "sev_severe"]


class _Constant:
    """Fallback when a training set has only one class."""

    def __init__(self, p: float):
        self.p = p

    def predict_proba(self, X):
        return np.column_stack([np.full(len(X), 1 - self.p), np.full(len(X), self.p)])


class TreeModel:
    def __init__(self, cfg: dict, feature_cols: list[str], heads: list[str] | None = None):
        self.cfg = cfg
        self.features = feature_cols
        self.heads = heads or LIKELIHOOD_HEADS + SEVERITY_HEADS
        self.models: dict = {}

    def _rows(self, df: pd.DataFrame, head: str) -> pd.DataFrame:
        return df[df["y_360"] == 1] if head in SEVERITY_HEADS else df

    def fit(self, df: pd.DataFrame) -> "TreeModel":
        m = self.cfg["model"]
        for head in self.heads:
            d = self._rows(df, head)
            y = d[head].to_numpy()
            pos, neg = int(y.sum()), int(len(y) - y.sum())
            if pos == 0 or neg == 0:
                self.models[head] = _Constant(float(pos > 0))
                continue
            clf = LGBMClassifier(
                n_estimators=m["n_estimators"],
                learning_rate=m["learning_rate"],
                num_leaves=m["num_leaves"],
                min_child_samples=m["min_child_samples"],
                subsample=m["subsample"],
                subsample_freq=1,
                colsample_bytree=m["colsample_bytree"],
                scale_pos_weight=neg / pos,
                random_state=self.cfg["seed"],
                verbose=-1,
            )
            clf.fit(d[self.features], y)
            self.models[head] = clf
        return self

    def predict(self, df: pd.DataFrame) -> pd.DataFrame:
        X = df[self.features]
        return pd.DataFrame({f"p_{h}": self.models[h].predict_proba(X)[:, 1] for h in self.heads}, index=df.index)

    def contributions(self, df: pd.DataFrame, head: str) -> pd.DataFrame:
        """Per-feature contribution to each prediction (log-odds), for explanations."""
        clf = self.models[head]
        if isinstance(clf, _Constant):
            return pd.DataFrame(0.0, index=df.index, columns=self.features)
        contrib = clf.predict_proba(df[self.features], pred_contrib=True)
        return pd.DataFrame(contrib[:, :-1], index=df.index, columns=self.features)
