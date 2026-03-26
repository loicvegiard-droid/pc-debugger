"""
Worker: System Log Analyzer
Reads Windows Event Logs (System + Application) for errors and warnings.
Runs in its own isolated interpreter — no shared state.
"""
import subprocess
import json


def run(max_events: int = 100) -> dict:
    """Entry point called by the orchestrator in an isolated interpreter."""
    result = {
        "worker": "logs",
        "status": "ok",
        "critical": [],
        "errors": [],
        "warnings": [],
    }

    query = (
        f"Get-WinEvent -LogName System,Application -MaxEvents {max_events} "
        "-ErrorAction SilentlyContinue "
        "| Where-Object { $_.Level -le 3 } "
        "| Select-Object TimeCreated,LevelDisplayName,ProviderName,Message "
        "| ConvertTo-Json -Depth 2"
    )

    try:
        ps = subprocess.run(
            ["powershell", "-NoProfile", "-Command", query],
            capture_output=True, text=True, timeout=45
        )
        if ps.returncode == 0 and ps.stdout.strip():
            events = json.loads(ps.stdout)
            if isinstance(events, dict):
                events = [events]
            for ev in events:
                level = ev.get("LevelDisplayName", "")
                entry = {
                    "time": ev.get("TimeCreated"),
                    "source": ev.get("ProviderName"),
                    "message": (ev.get("Message") or "")[:200],
                }
                if level == "Critical":
                    result["critical"].append(entry)
                elif level == "Error":
                    result["errors"].append(entry)
                elif level == "Warning":
                    result["warnings"].append(entry)

    except Exception as exc:
        result["status"] = "error"
        result["errors"].append({"exception": str(exc)})

    if result["critical"] or result["errors"]:
        result["status"] = "issues_found"

    return result
