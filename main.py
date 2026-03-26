"""
PC Debugger — Main Orchestrator
================================
Runs all workers in parallel using Python 3.14's InterpreterPoolExecutor.

Each worker gets its own ISOLATED Python interpreter:
  - No shared GIL          (free-threaded 3.14t build)
  - No shared memory       (true interpreter isolation)
  - True parallel execution across all CPU cores

Tree:
    pc-debugger/
    ├── main.py               ← you are here
    ├── pyproject.toml
    ├── .python-version       (3.14t)
    └── workers/
        ├── driver.py         → broken/missing drivers
        ├── logs.py           → Windows event log errors
        ├── processes.py      → CPU/RAM hogs + crash dumps
        └── network.py        → adapter + suspicious connections

Usage:
    uv run main.py
    uv run main.py --json          # raw JSON output
    uv run main.py --worker logs   # single worker only
"""

import sys
import json
import argparse
import importlib
from concurrent.futures import InterpreterPoolExecutor

# All available workers
WORKERS = ["driver", "logs", "processes", "network"]


def _run_worker(worker_name: str) -> dict:
    """
    This function executes inside an isolated interpreter.
    It imports the worker module fresh — no shared state with other workers.
    """
    mod = importlib.import_module(f"workers.{worker_name}")
    return mod.run()


def run_all(workers: list[str], max_workers: int | None = None) -> list[dict]:
    """Launch all workers in parallel isolated interpreters."""
    results = []
    n = max_workers or len(workers)

    with InterpreterPoolExecutor(max_workers=n) as pool:
        futures = {
            pool.submit(_run_worker, name): name
            for name in workers
        }
        for future in futures:
            try:
                results.append(future.result(timeout=60))
            except Exception as exc:
                results.append({
                    "worker": futures[future],
                    "status": "error",
                    "error": str(exc),
                })

    return results


def print_report(results: list[dict]) -> None:
    """Pretty-print the diagnostic report."""
    try:
        from rich.console import Console
        from rich.table import Table
        from rich import box

        console = Console()
        console.print("\n[bold cyan]PC Debugger — Diagnostic Report[/bold cyan]\n")

        for r in results:
            worker = r.get("worker", "?").upper()
            status = r.get("status", "?")
            color = "green" if status == "ok" else ("red" if status == "issues_found" else "yellow")
            console.print(f"[bold {color}]▶ {worker}[/bold {color}] — status: [{color}]{status}[/{color}]")

            for key, val in r.items():
                if key in ("worker", "status"):
                    continue
                if isinstance(val, list) and val:
                    console.print(f"  [dim]{key}:[/dim]")
                    for item in val[:5]:  # limit to first 5
                        console.print(f"    • {item}")
                    if len(val) > 5:
                        console.print(f"    … and {len(val) - 5} more")
                elif val is not None:
                    console.print(f"  [dim]{key}:[/dim] {val}")
            console.print()

    except ImportError:
        # Fallback if rich is not installed
        for r in results:
            print(f"\n=== {r.get('worker', '?').upper()} [{r.get('status')}] ===")
            for k, v in r.items():
                if k not in ("worker", "status"):
                    print(f"  {k}: {v}")


def main() -> None:
    parser = argparse.ArgumentParser(description="PC Debugger — parallel isolated workers")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    parser.add_argument("--worker", choices=WORKERS, help="Run a single worker only")
    parser.add_argument("--max-workers", type=int, default=None, help="Max parallel interpreters")
    args = parser.parse_args()

    targets = [args.worker] if args.worker else WORKERS

    print(f"Launching {len(targets)} worker(s) in isolated interpreters (Python 3.14t)…")
    results = run_all(targets, max_workers=args.max_workers)

    if args.json:
        print(json.dumps(results, indent=2, default=str))
    else:
        print_report(results)

    # Exit with error code if any issues found
    has_issues = any(r.get("status") not in ("ok",) for r in results)
    sys.exit(1 if has_issues else 0)


if __name__ == "__main__":
    main()
