#!/usr/bin/env python3
import json
import subprocess
import sys


def hyprctl_json(*args):
    try:
        output = subprocess.check_output(["hyprctl", "-j", *args], text=True)
        return json.loads(output)
    except Exception:
        return None


def regular_workspace_id(workspace):
    if not isinstance(workspace, dict):
        return 0

    name = str(workspace.get("name") or "")
    if name.startswith("special:"):
        return 0

    try:
        workspace_id = int(workspace.get("id") or 0)
    except (TypeError, ValueError):
        return 0

    return workspace_id if workspace_id > 0 else 0


def main():
    try:
        direction = int(sys.argv[1])
    except (IndexError, TypeError, ValueError):
        return 0

    direction = 1 if direction > 0 else -1

    active = hyprctl_json("activeworkspace") or {}
    current_id = regular_workspace_id(active) or 1

    max_occupied_id = 0
    clients = hyprctl_json("clients") or []
    for client in clients:
        workspace_id = regular_workspace_id(client.get("workspace") if isinstance(client, dict) else None)
        if workspace_id > max_occupied_id:
            max_occupied_id = workspace_id

    max_target_id = max(1, max_occupied_id + 1)
    target_id = max(1, min(current_id + direction, max_target_id))
    if target_id == current_id:
        return 0

    subprocess.run(["hyprctl", "dispatch", "workspace", str(target_id)], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
