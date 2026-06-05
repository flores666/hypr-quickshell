#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
qs -p ./shell.qml
