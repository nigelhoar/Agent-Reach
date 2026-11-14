#!/usr/bin/env bash
# Run once via Azure VM RunCommand: finish private Paperclip installation,
# stage project evidence reconciler, run its regression tests, verify service.
# Cloudflare, production application repos and autonomous agents untouched.
set -euo pipefail
test "$(id -un)" = root
H=/home/tepilot
DIR="$H/paperclip-cos/project-intelligence"
REF=c4c58ce47760d58b0af1d0821ce6d2d750cdc4d2
BASE="https://raw.githubusercontent.com/nigelhoar/Agent-Reach/$REF/deploy/te-autonomous-pilot"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$H"
echo "=== FETCH PINNED BOOTSTRAP ==="
curl -fsSL --retry 3 "$BASE/install-paperclip-cos.sh" -o "$TMP/install-paperclip.sh"
bash -n "$TMP/install-paperclip.sh"
echo "INSTALL_SCRIPT=SYNTAX_OK"
echo "=== INSTALL OR VERIFY PAPERCLIP ==="
bash "$TMP/install-paperclip.sh"

echo "=== STAGE PRIVATE EVIDENCE RECONCILER ==="
install -d -m 0700 -o tepilot -g tepilot "$H/paperclip-cos" "$DIR"
for NAME in reconcile-evidence.mjs reconcile-evidence.test.mjs PROJECT-INTELLIGENCE.md; do
  curl -fsSL --retry 3 "$BASE/$NAME" -o "$TMP/$NAME"
  install -m 0600 -o tepilot -g tepilot "$TMP/$NAME" "$DIR/$NAME"
done
echo "=== REGRESSION TESTS ==="
(
  cd "$DIR"
  runuser -u tepilot -- env HOME="$H" \
    PATH="/opt/te-paperclip/node/bin:/usr/local/bin:/usr/bin:/bin" \
    /opt/te-paperclip/node/bin/node --test "$DIR/reconcile-evidence.test.mjs"
)
echo "=== FINAL HEALTH CHECKS ==="
systemctl is-active --quiet te-paperclip-cos.service
curl -fsS --max-time 12 "http://127.0.0.1:3100/api/health" >/dev/null
python3 - <<'PY'
import subprocess
lines=subprocess.check_output(["ss","-ltn"], text=True).splitlines()
ports=[x for x in lines if ":3100 " in x]
if not ports:
    raise SystemExit("Paperclip is not listening on port 3100")
if any("0.0.0.0:3100" in x or "[::]:3100" in x or "*:3100" in x for x in ports):
    raise SystemExit("Paperclip is not bound solely to loopback")
print("PAPERCLIP_LISTENER=PRIVATE")
PY
echo "PAPERCLIP_SERVICE=ACTIVE"
echo "PAPERCLIP_HEALTH=OK"
echo "PROJECT_INTELLIGENCE_TESTS=PASS"
echo "CHATGPT_HISTORY_SYNC=NOT_YET_CONNECTED"
echo "AUTONOMOUS_PROJECT_JOBS=NOT_YET_ENABLED"
echo "SHELL_BOOTSTRAP_COMPLETE"
