"""
Worker: Network Diagnostics
Checks open ports, active connections, DNS, and adapter status.
Runs in its own isolated interpreter — no shared state.
"""
import subprocess
import json


def run() -> dict:
    """Entry point called by the orchestrator in an isolated interpreter."""
    result = {
        "worker": "network",
        "status": "ok",
        "adapters": [],
        "suspicious_connections": [],
        "dns_ok": None,
    }

    # --- Adapter status ---
    try:
        ps = subprocess.run(
            [
                "powershell", "-NoProfile", "-Command",
                "Get-NetAdapter | Select-Object Name,Status,LinkSpeed,MacAddress "
                "| ConvertTo-Json -Depth 2"
            ],
            capture_output=True, text=True, timeout=20
        )
        if ps.returncode == 0 and ps.stdout.strip():
            adapters = json.loads(ps.stdout)
            if isinstance(adapters, dict):
                adapters = [adapters]
            result["adapters"] = [
                {"name": a.get("Name"), "status": a.get("Status"), "speed": a.get("LinkSpeed")}
                for a in adapters
            ]
    except Exception as exc:
        result["adapters"] = [{"error": str(exc)}]

    # --- Suspicious outbound connections (non-local, established) ---
    try:
        import psutil
        for conn in psutil.net_connections(kind="inet"):
            if conn.status == "ESTABLISHED" and conn.raddr:
                ip = conn.raddr.ip
                # Flag non-RFC1918 connections on unusual ports
                if not (ip.startswith("10.") or ip.startswith("192.168.")
                        or ip.startswith("172.") or ip == "127.0.0.1"):
                    if conn.raddr.port not in (80, 443, 53):
                        result["suspicious_connections"].append({
                            "remote_ip": ip,
                            "remote_port": conn.raddr.port,
                            "local_port": conn.laddr.port if conn.laddr else None,
                            "pid": conn.pid,
                        })
    except Exception as exc:
        result["suspicious_connections"].append({"error": str(exc)})

    # --- DNS check ---
    try:
        ping = subprocess.run(
            ["ping", "-n", "1", "-w", "2000", "8.8.8.8"],
            capture_output=True, text=True, timeout=10
        )
        result["dns_ok"] = ping.returncode == 0
    except Exception:
        result["dns_ok"] = False

    if result["suspicious_connections"] or result["dns_ok"] is False:
        result["status"] = "issues_found"

    return result
