"""
Worker: Driver Inspector
Scans for missing, broken, or outdated drivers.
Runs in its own isolated interpreter — no shared state.
"""
import subprocess
import json


def run() -> dict:
    """Entry point called by the orchestrator in an isolated interpreter."""
    result = {
        "worker": "driver",
        "status": "ok",
        "issues": [],
        "info": [],
    }

    try:
        # Query all PnP devices and their status
        ps = subprocess.run(
            [
                "powershell", "-NoProfile", "-Command",
                "Get-PnpDevice | Select-Object Status,Class,FriendlyName,InstanceId "
                "| ConvertTo-Json -Depth 2"
            ],
            capture_output=True, text=True, timeout=30
        )
        if ps.returncode == 0 and ps.stdout.strip():
            devices = json.loads(ps.stdout)
            if isinstance(devices, dict):
                devices = [devices]
            for dev in devices:
                status = dev.get("Status", "")
                name = dev.get("FriendlyName") or dev.get("InstanceId", "Unknown")
                if status in ("Error", "Degraded", "Unknown"):
                    result["issues"].append(
                        {"device": name, "status": status, "class": dev.get("Class")}
                    )
                elif status == "OK":
                    result["info"].append(name)
        else:
            result["issues"].append({"error": "PowerShell unavailable or no output"})

    except Exception as exc:
        result["status"] = "error"
        result["issues"].append({"exception": str(exc)})

    if result["issues"]:
        result["status"] = "issues_found"

    return result
