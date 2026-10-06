#!/usr/bin/env python3
"""Pairwise island-versus-baseline verdicts from benchmark-resources.py runs.

A directory holds `<cohort>-island-false-<n>.json` / `<cohort>-island-true-<n>.json`
pairs. For each pair the owned processes (every sampled process except the one
labelled "compositor", or the lowest PID in an unlabelled run) are summed per
sample, so the figures describe simultaneous footprints, and the medians of
those sums are subtracted. CPU is the whole-run interval-weighted mean.

A memory budget is judged against the cohort's own noise: the spread of the
baseline's owned footprint across its pairs. The verdict is `pass` only when
the median delta clears the budget by more than that spread, `FAIL` only when
it exceeds the budget by more than it, and `inconclusive` otherwise, or with
fewer than three pairs; an inconclusive cohort needs more pairs, not a
conclusion. USS and anonymous PSS deltas (a process's own pages, unmoved by
other processes mapping the same libraries) are reported for attribution.
Within every island run the owned PSS of the last fifth of samples is compared
with the first fifth; a rise over 5 MiB is reported as growth and fails.

Exit status: 0 when every cohort passes, 1 when any fails, 2 when none fails
but some are inconclusive.
"""
import argparse
import json
import os
import statistics
import sys

MiB = 1024
CPU_BUDGET = {"collapsed-paused": 0.5, "collapsed-playing": 2.0, "expanded-playing": 2.0,
              "hover-cycle": 5.0, "camera-open": 5.0, "calendar-open": 2.0}
MEMORY_BUDGET = {"pssKiB": 25.0, "rssKiB": 40.0}
GROWTH_LIMIT = 5.0
MIN_PAIRS = 3


def owned(run):
    ids = list(run["summary"])
    roles = run.get("roles") or {}
    if roles:
        compositor = [pid for pid in ids if roles.get(pid) == "compositor"]
    else:
        compositor = [min(ids, key=int)] if ids else []
    return [pid for pid in ids if pid not in compositor], compositor


def sums(run, key, pids):
    return [sum(sample["processes"].get(pid, {}).get(key, 0) for pid in pids) for sample in run["samples"]]


def recorded(run, key):
    return all(key in values for sample in run["samples"] for values in sample["processes"].values())


def median_mib(run, key):
    pids, _ = owned(run)
    return statistics.median(sums(run, key, pids)) / MiB


def cpu(run):
    pids, compositor = owned(run)
    return (sum(run["summary"][pid]["cpuPercentMean"] for pid in pids),
            sum(run["summary"][pid]["cpuPercentMean"] for pid in compositor))


def growth_mib(run):
    pids, _ = owned(run)
    totals = sums(run, "pssKiB", pids)
    fifth = max(1, len(totals) // 5)
    return (statistics.median(totals[-fifth:]) - statistics.median(totals[:fifth])) / MiB


def judge(delta, noise, budget, pairs):
    if pairs < MIN_PAIRS:
        return "inconclusive"
    if delta + noise <= budget:
        return "pass"
    if delta - noise > budget:
        return "FAIL"
    return "inconclusive"


def analyse(directory, cohort):
    pairs = []
    for index in range(1, 100):
        base = os.path.join(directory, f"{cohort}-island-false-{index}.json")
        island = os.path.join(directory, f"{cohort}-island-true-{index}.json")
        if not (os.path.exists(base) and os.path.exists(island)):
            break
        with open(base) as a, open(island) as b:
            pairs.append((json.load(a), json.load(b)))
    if not pairs:
        return None
    result = {"cohort": cohort, "pairs": len(pairs), "metrics": {}}
    for key in ("pssKiB", "rssKiB", "ussKiB", "pssAnonKiB"):
        # Runs from before the sampler recorded USS and anonymous PSS lack them.
        if not all(recorded(run, key) for pair in pairs for run in pair):
            result["metrics"][key] = None
            continue
        deltas = [median_mib(island, key) - median_mib(base, key) for base, island in pairs]
        baselines = [median_mib(base, key) for base, _ in pairs]
        result["metrics"][key] = {"median": statistics.median(deltas), "min": min(deltas), "max": max(deltas),
                                  "noise": max(baselines) - min(baselines)}
    cpu_deltas = [cpu(island)[0] - cpu(base)[0] for base, island in pairs]
    compositor_deltas = [cpu(island)[1] - cpu(base)[1] for base, island in pairs]
    result["cpu"] = statistics.median(cpu_deltas)
    result["compositor"] = statistics.median(compositor_deltas)
    result["growth"] = max(growth_mib(island) for _, island in pairs)
    verdicts = {"cpu": "pass" if result["cpu"] <= CPU_BUDGET.get(cohort, float("inf")) else "FAIL"}
    for key, budget in MEMORY_BUDGET.items():
        metric = result["metrics"][key]
        verdicts[key] = judge(metric["median"], metric["noise"], budget, len(pairs))
    verdicts["growth"] = "pass" if result["growth"] <= GROWTH_LIMIT else "FAIL"
    result["verdicts"] = verdicts
    values = verdicts.values()
    result["verdict"] = "FAIL" if "FAIL" in values else "inconclusive" if "inconclusive" in values else "pass"
    return result


def table(results):
    lines = ["| Cohort | Pairs | Owned CPU pp | Compositor pp | PSS MiB (median [range] ± noise) "
             "| RSS MiB (median [range] ± noise) | USS MiB | Anon PSS MiB | Growth MiB | Verdict |",
             "|---|---|---|---|---|---|---|---|---|---|"]

    def memory(metric):
        return f"{metric['median']:.1f} [{metric['min']:.1f}, {metric['max']:.1f}] ± {metric['noise']:.1f}"

    for r in results:
        m, v = r["metrics"], r["verdicts"]
        detail = ", ".join(f"{name}: {verdict}" for name, verdict in v.items() if verdict != "pass")
        def own(key):
            return "n/a" if m[key] is None else f"{m[key]['median']:.1f}"
        lines.append(f"| {r['cohort']} | {r['pairs']} | {r['cpu']:.2f} | {r['compositor']:.2f} | {memory(m['pssKiB'])} "
                     f"| {memory(m['rssKiB'])} | {own('ussKiB')} | {own('pssAnonKiB')} "
                     f"| {r['growth']:.1f} | {r['verdict']}{' (' + detail + ')' if detail else ''} |")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory")
    parser.add_argument("--cohort", action="append", help="cohort to analyse (default: every budgeted cohort)")
    args = parser.parse_args(argv)
    results = [r for r in (analyse(args.directory, c) for c in (args.cohort or CPU_BUDGET)) if r]
    if not results:
        print("no complete baseline/island pairs found", file=sys.stderr)
        return 2
    print(table(results))
    verdicts = [r["verdict"] for r in results]
    return 1 if "FAIL" in verdicts else 2 if "inconclusive" in verdicts else 0


if __name__ == "__main__":
    sys.exit(main())
