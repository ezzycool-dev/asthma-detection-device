"""Planned model: a shallow two-branch GRU (next step, not yet trained).

Why two branches: the signals move at different speeds.
  fast branch  HR, RR, wheeze over the last 60 minutes
  slow branch  histamine and S1P trends over the last 24 hours
Each input is multiplied by its quality score first, so a missing or noisy
stream contributes little. The two summaries are joined with context and
profile features, then feed the same five outputs as the tree model.

It is kept shallow (1-2 layers, 32-64 units) because the real dataset is small.
It is only adopted if it beats the tree model on sensitivity, false alarms
per day and lead time under the same leave-one-person-out testing.

Requires the optional dependency:  pip install -e ".[gru]"
"""

from __future__ import annotations

try:
    import torch
    from torch import nn
except ImportError:  # torch is optional
    torch = None
    nn = None


if nn is not None:

    class TwoBranchGRU(nn.Module):
        def __init__(self, n_fast: int, n_slow: int, n_static: int, hidden: int = 48, n_heads: int = 5):
            super().__init__()
            self.fast = nn.GRU(n_fast, hidden, num_layers=1, batch_first=True)
            self.slow = nn.GRU(n_slow, hidden, num_layers=1, batch_first=True)
            self.head = nn.Sequential(nn.Linear(2 * hidden + n_static, hidden), nn.ReLU(), nn.Linear(hidden, n_heads))

        def forward(self, fast, fast_q, slow, slow_q, static):
            """fast: (batch, 60, n_fast); slow: (batch, 288, n_slow) at 5-min steps;
            *_q: matching quality scores in [0, 1]; static: (batch, n_static).
            Returns logits for [y_15, y_60, y_360, sev_moderate, sev_severe]."""
            _, h_fast = self.fast(fast * fast_q)
            _, h_slow = self.slow(slow * slow_q)
            z = torch.cat([h_fast[-1], h_slow[-1], static], dim=1)
            return self.head(z)
