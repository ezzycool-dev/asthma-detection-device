"""Early warning of allergy-induced asthma attacks.

Pipeline (one module per step):
    data      -> load AAMOS-00 and put everything on a 1-minute grid
    labels    -> turn clinical events into mild / moderate / severe episodes (ATS/ERS)
    synthetic -> generate histamine, S1P, RR and wheeze-score signals around real episodes
    baseline  -> personal day/night baselines with a population prior and guardrails
    features  -> causal (no look-ahead) features per signal
    dataset   -> training examples and targets per prediction window
    models    -> gradient-boosted trees (baseline) and a two-branch GRU (next step)
    evaluate  -> leave-one-person-out testing and metrics
    alerts    -> user / EMS alert logic with cooldown and countdown
    explain   -> "Why now?" explanations
"""

__version__ = "0.1.0"
