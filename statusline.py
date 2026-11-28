#!/usr/bin/env python3
"""Antigravity CLI custom 2-line statusline script.

Line 1: Current context usage bar and primary quota bar.
Line 2: Current folder, git branch/status, and daily/weekly/monthly quotas.
"""

import json
import os
import subprocess
import sys

RST = "\033[0m"
DIM = "\033[2m"
BOLD = "\033[1m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"


def bar(pct: float, width: int = 12, invert_color: bool = False) -> str:
    """Render an ANSI-colored progress bar for a percentage in [0, 100]."""
    pct = max(0.0, min(100.0, pct))
    filled = round((pct / 100.0) * width)
    if invert_color:
        color = GREEN if pct >= 50 else (YELLOW if pct >= 20 else RED)
    else:
        color = GREEN if pct < 60 else (YELLOW if pct < 85 else RED)
    return f"{color}{'█' * filled}{DIM}{'░' * (width - filled)}{RST}"


def get_git_status(cwd: str) -> str:
    """Return formatted git branch and dirty-file count, or empty string if not a repo."""
    try:
        res = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain", "-b"],
            capture_output=True,
            text=True,
            timeout=1.5,
        )
        if res.returncode != 0:
            return ""
        lines = res.stdout.splitlines()
        if not lines:
            return ""
        branch_line = lines[0].removeprefix("## ").split("...")[0]
        dirty = len(lines) - 1
        marker = f" {YELLOW}*{dirty}{RST}" if dirty > 0 else f" {GREEN}✓{RST}"
        return f"{MAGENTA}{branch_line}{RST}{marker}"
    except Exception:
        return ""


def extract_quota_pct(bucket: dict) -> float | None:
    """Extract remaining quota percentage from a quota bucket dict."""
    if not isinstance(bucket, dict) or bucket.get("disabled"):
        return None
    if "remaining_fraction" in bucket and bucket["remaining_fraction"] is not None:
        return float(bucket["remaining_fraction"]) * 100.0
    if "used_percentage" in bucket and bucket["used_percentage"] is not None:
        return max(0.0, 100.0 - float(bucket["used_percentage"]))
    return None


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    # Line 1: Context bar + Quota bar
    cw = data.get("context_window") or {}
    ctx_pct = cw.get("used_percentage")
    if ctx_pct is None:
        size = cw.get("context_window_size") or 0
        used = cw.get("total_input_tokens") or 0
        ctx_pct = (used / size * 100.0) if size else 0.0
    ctx_pct = float(ctx_pct)

    quotas = data.get("quota") or data.get("rate_limits") or {}
    primary_quota = extract_quota_pct(quotas)
    if primary_quota is None and isinstance(quotas, dict):
        for val in quotas.values():
            primary_quota = extract_quota_pct(val)
            if primary_quota is not None:
                break

    ctx_str = f"{CYAN}Ctx{RST} [{bar(ctx_pct)}] {ctx_pct:.0f}%"
    if primary_quota is not None:
        q_str = f"{BLUE}Quota{RST} [{bar(primary_quota, invert_color=True)}] {primary_quota:.0f}%"
    else:
        q_str = f"{BLUE}Quota{RST} [{DIM}{'░' * 12}{RST}] --"
    line1 = f"{ctx_str}  {DIM}|{RST}  {q_str}"

    # Line 2: Folder + Git status + Daily/Weekly/Monthly quotas
    cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or os.getcwd()
    folder = os.path.basename(cwd.rstrip("/")) or cwd
    git_str = get_git_status(cwd)

    period_parts = []
    for label, keywords in [("D", ("day", "daily")), ("W", ("week", "weekly")), ("M", ("month", "monthly"))]:
        val = None
        if isinstance(quotas, dict):
            for key, bucket in quotas.items():
                if any(kw in key.lower() for kw in keywords):
                    val = extract_quota_pct(bucket)
                    if val is not None:
                        break
        period_parts.append(f"{label}:{val:.0f}%" if val is not None else f"{label}:--")

    git_part = f" {git_str}" if git_str else ""
    line2 = f"{BOLD}{folder}{RST}{git_part}  {DIM}|{RST}  {' '.join(period_parts)}"
    print(f"{line1}\n{line2}")


if __name__ == "__main__":
    main()
