#!/usr/bin/env python3
"""Bounded read-only process sampling. 100% CPU means one logical core.

Memory is recorded four ways per process: RSS, PSS, anonymous PSS and USS
(private clean + private dirty pages). PSS moves when another process maps or
unmaps the same libraries; anonymous PSS and USS are the process's own memory
and are the stable basis for attributing a delta (see analyze-resources.py).
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import time


MEMORY = ("rssKiB", "pssKiB", "pssAnonKiB", "ussKiB")


def parse_pid(value):
    role, _, pid = value.rpartition(":")
    if not pid.isdigit() or (role and not role.replace("-", "").isalnum()):
        raise argparse.ArgumentTypeError("expected PID or ROLE:PID")
    return role, int(pid)


def sample(pid):
    proc = Path("/proc") / str(pid)
    fields = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    memory = {"rssKiB": 0, "pssKiB": 0, "pssAnonKiB": 0, "ussKiB": 0}
    names = {"Rss:": "rssKiB", "Pss:": "pssKiB", "Pss_Anon:": "pssAnonKiB",
             "Private_Clean:": "ussKiB", "Private_Dirty:": "ussKiB"}
    for line in (proc / "smaps_rollup").read_text().splitlines():
        pair = line.split()
        if pair and pair[0] in names:
            memory[names[pair[0]]] += int(pair[1])
    return {"ticks": int(fields[11]) + int(fields[12]), "startTicks": int(fields[19]), **memory}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    # PID, or ROLE:PID to label it (the analyzer leaves a "compositor" out of
    # the owned total and reports it beside it).
    parser.add_argument("--pid", action="append", type=parse_pid, required=True)
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--warmup", type=int, default=30)
    parser.add_argument("--cohort", required=True)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 1800 or not 0 <= args.warmup <= 300:
        parser.error("duration outside bounded sampling range")
    roles = {pid: role for role, pid in args.pid if role}
    pids = list(dict.fromkeys(pid for _, pid in args.pid))
    initial = {pid: sample(pid) for pid in pids}
    # Warmup is interruptible. This program owns no target process and kills none.
    for _ in range(args.warmup):
        time.sleep(1)
    previous_time = time.monotonic()
    previous = {pid: sample(pid) for pid in pids}
    rows = []
    ticks_per_second = os.sysconf("SC_CLK_TCK")
    for _ in range(args.seconds):
        time.sleep(1)
        now = time.monotonic()
        current = {pid: sample(pid) for pid in pids}
        row = {"elapsedSeconds": now - previous_time, "processes": {}}
        for pid in pids:
            if current[pid]["startTicks"] != initial[pid]["startTicks"]:
                raise RuntimeError("PID lifetime changed; run invalid")
            row["processes"][pid] = {
                "cpuPercent": 100 * (current[pid]["ticks"] - previous[pid]["ticks"])
                    / ticks_per_second / (now - previous_time),
                **{name: current[pid][name] for name in MEMORY}}
        rows.append(row)
        previous, previous_time = current, now
    summary = {}
    measured_seconds = sum(row["elapsedSeconds"] for row in rows)
    for pid in pids:
        summary[pid] = {name + "Median": statistics.median(row["processes"][pid][name] for row in rows)
                        for name in ("cpuPercent", *MEMORY)}
        # Budget comparisons use whole-run CPU, not the median of mostly-idle
        # one-second buckets (which would conceal intermittent expensive work).
        summary[pid]["cpuPercentMean"] = sum(row["processes"][pid]["cpuPercent"] * row["elapsedSeconds"]
                                                  for row in rows) / measured_seconds
        summary[pid]["rssKiBPeak"] = max(row["processes"][pid]["rssKiB"] for row in rows)
        summary[pid]["pssKiBPeak"] = max(row["processes"][pid]["pssKiB"] for row in rows)
    print(json.dumps({"schemaVersion": 2, "cohort": args.cohort, "clock": "monotonic",
                      "roles": {str(pid): role for pid, role in roles.items()},
                      "cpuUnit": "percent-of-one-core", "warmupSeconds": args.warmup,
                      "measuredSeconds": measured_seconds, "summary": summary, "samples": rows}, separators=(",", ":")))


if __name__ == "__main__":
    main()
