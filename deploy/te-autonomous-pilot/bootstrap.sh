#!/usr/bin/env bash
# Taylor Emmet: LOW-COST autonomous coding evaluation. No model calls are made.
# Use only on the dedicated TE-IT-Dev VM. Run as root via Azure VM RunCommand.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT=/opt/te-ai-pilot
HOME_DIR=/home/tepilot
echo "=== Install basic prerequisites (no AI charges) ==="
apt-get update -qq
apt-get install -y -qq ca-certificates curl jq git tmux xz-utils iptables python3

if ! id tepilot >/dev/null 2>&1; then
  useradd --create-home --user-group --shell /bin/bash tepilot
fi
# TE-IT-Dev VM has an Azure managed identity. Do not expose its IMDS endpoint
# to the unprivileged coding worker account. Maintain rule across reboots.
cat >/etc/systemd/system/te-ai-pilot-block-imds.service <<'UNIT'
[Unit]
Description=Block Azure VM managed identity from nonprivileged coding pilot
Before=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/usr/sbin/iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT 2>/dev/null || /usr/sbin/iptables -I OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT'
ExecStop=/bin/sh -c '/usr/sbin/iptables -D OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT

echo "=== Install checksum-verified Node 22 without modifying system Node ==="
mkdir -p "$ROOT"
if [ ! -x "$ROOT/node/bin/node" ]; then
  TEMP="$(mktemp -d)"
  trap 'rm -rf "$TEMP"' EXIT
  curl -fsSL --retry 3 https://nodejs.org/dist/index.json -o "$TEMP/index.json"
  VERSION="$(jq -er '[.[] | select(.version | startswith("v22."))][0].version' "$TEMP/index.json")"
  BASE="https://nodejs.org/dist/$VERSION"
  ARCHIVE="node-$VERSION-linux-x64.tar.xz"
  curl -fsSL --retry 3 "$BASE/$ARCHIVE" -o "$TEMP/$ARCHIVE"
  curl -fsSL --retry 3 "$BASE/SHASUMS256.txt" -o "$TEMP/SHASUMS256.txt"
  (cd "$TEMP"; grep -F "  $ARCHIVE" SHASUMS256.txt | sha256sum -c -)
  mkdir -p "$ROOT/node"
  tar -xJf "$TEMP/$ARCHIVE" -C "$ROOT/node" --strip-components=1
fi
"$ROOT/node/bin/node" --version

echo "=== Install Codex and ORCH packages as non-root user ==="
runuser -u tepilot -- env HOME="$HOME_DIR" PATH="$ROOT/node/bin:/usr/local/bin:/usr/bin:/bin" \
  npm install --prefix "$HOME_DIR/.local" --no-audit --no-fund \
  @openai/codex @oxgeneral/orch

echo "=== Install AoE official stable release as non-root user ==="
curl -fsSL --retry 3 \
  https://raw.githubusercontent.com/agent-of-empires/agent-of-empires/main/scripts/install.sh \
  -o "$ROOT/aoe-official-install.sh"
chmod 0644 "$ROOT/aoe-official-install.sh"
runuser -u tepilot -- env HOME="$HOME_DIR" \
  PATH="$ROOT/node/bin:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
  bash "$ROOT/aoe-official-install.sh"

echo "=== Prepare intentionally synthetic local benchmark repo ==="
install -d -m 0700 -o tepilot -g tepilot "$HOME_DIR/benchmark"
if [ ! -d "$HOME_DIR/benchmark/.git" ]; then
  mkdir -p "$HOME_DIR/benchmark/tests"
  cat > "$HOME_DIR/benchmark/task_queue.py" <<'PY'
"""Synthetic task queue. No clients, secrets, or TE source data."""

def unique_tasks(tasks):
    """Return tasks once each, preserving their original order."""
    return list(tasks)  # TODO: fix duplicate handling
PY
  cat > "$HOME_DIR/benchmark/tests/test_task_queue.py" <<'PY'
import unittest
from task_queue import unique_tasks

class QueueTests(unittest.TestCase):
    def test_preserves_order(self):
        self.assertEqual(unique_tasks(["security", "build"]), ["security", "build"])

    def test_removes_duplicates(self):
        self.assertEqual(unique_tasks(["build", "test", "build"]), ["build", "test"])
PY
  cat > "$HOME_DIR/benchmark/AGENTS.md" <<'TXT'
Synthetic benchmark only. Do not read other directories, access Azure,
use credentials, install packages, contact external services, or deploy.
Fix the duplicate handling in task_queue.py while preserving order.
Run python3 -m unittest discover -s tests -v. Do not modify any other repo.
TXT
  chown -R tepilot:tepilot "$HOME_DIR/benchmark"
  runuser -u tepilot -- git -C "$HOME_DIR/benchmark" init -q
  runuser -u tepilot -- git -C "$HOME_DIR/benchmark" config user.name "TE Agent Pilot"
  runuser -u tepilot -- git -C "$HOME_DIR/benchmark" config user.email "tepilot@localhost"
  runuser -u tepilot -- git -C "$HOME_DIR/benchmark" add .
  runuser -u tepilot -- git -C "$HOME_DIR/benchmark" commit -qm "Synthetic baseline (one failing test)"
fi

echo "=== Installed versions ==="
runuser -u tepilot -- env HOME="$HOME_DIR" PATH="$ROOT/node/bin:$HOME_DIR/.local/bin:$HOME_DIR/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  bash -c '
  printf "Codex: "; "$HOME/.local/node_modules/.bin/codex" --version
  printf "ORCH: "; "$HOME/.local/node_modules/.bin/orch" --version || true
  printf "AoE: "; "$HOME/.local/bin/aoe" --version
  echo "Running synthetic baseline test (failure expected):"
  cd "$HOME/benchmark"; python3 -m unittest discover -s tests -v || true
'
echo "SETUP COMPLETE. No AI prompts sent and no billable API credentials configured."
echo "Next: sign into Codex with ChatGPT as tepilot using device authentication."
