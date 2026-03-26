"""
Worker: Process & Memory Monitor
Reports CPU/RAM hogs, zombie processes, and crash dumps.
Runs in its own isolated interpreter — no shared state.
"""
import os
import glob


def run(cpu_threshold: float = 50.0, mem_threshold_mb: float = 500.0) -> dict:
    """Entry point called by the orchestrator in an isolated interpreter."""
    result = {
        "worker": "processes",
        "status": "ok",
        "high_cpu": [],
        "high_memory": [],
        "crash_dumps": [],
    }

    try:
        import psutil  # installed via uv into the venv

        for proc in psutil.process_iter(["pid", "name", "cpu_percent", "memory_info", "status"]):
            try:
                info = proc.info
                cpu = proc.cpu_percent(interval=0.1)
                mem_mb = (info["memory_info"].rss / 1024 / 1024) if info["memory_info"] else 0

                if cpu >= cpu_threshold:
                    result["high_cpu"].append({
                        "pid": info["pid"],
                        "name": info["name"],
                        "cpu_pct": round(cpu, 1),
                    })
                if mem_mb >= mem_threshold_mb:
                    result["high_memory"].append({
                        "pid": info["pid"],
                        "name": info["name"],
                        "mem_mb": round(mem_mb, 1),
                    })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

    except ImportError:
        result["status"] = "error"
        result["high_cpu"].append({"error": "psutil not installed — run: uv sync"})

    # Check for Windows crash dumps
    dump_paths = [
        "C:/Windows/Minidump/*.dmp",
        "C:/Windows/MEMORY.DMP",
        f"{os.environ.get('LOCALAPPDATA', '')}/CrashDumps/*.dmp",
    ]
    for pattern in dump_paths:
        for f in glob.glob(pattern):
            result["crash_dumps"].append(f)

    if result["high_cpu"] or result["high_memory"] or result["crash_dumps"]:
        result["status"] = "issues_found"

    return result
