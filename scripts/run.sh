#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
qs -p "$HOME/hypr-quickshell/shell.qml"
