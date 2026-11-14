#!/usr/bin/env bash
# Guard for ORCH v1.0.34 Codex adapter. Install as root-owned "codex"
# ahead of the original Codex binary in PATH during the synthetic pilot.
set -euo pipefail
REAL=/home/tepilot/.local/node_modules/.bin/codex
if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
  exec "$REAL" --version
fi
if [ "$#" -lt 1 ] || [ "$1" != "exec" ]; then
  echo "PILOT_GUARD: unexpected Codex invocation refused" >&2
  exit 41
fi
case "$(pwd -P)" in
  /home/tepilot/comparisons/orch|/home/tepilot/comparisons/orch/*) ;;
  *) echo "PILOT_GUARD: working directory not synthetic benchmark" >&2; exit 42;;
esac
shift
ARGS=(exec --config 'approval_policy="never"')
SEEN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sandbox)
      [ "$#" -ge 2 ] || exit 43
      case "$2" in
        danger-full-access|workspace-write) ;;
        *) echo "PILOT_GUARD: unsupported sandbox" >&2; exit 44;;
      esac
      ARGS+=(--sandbox workspace-write)
      SEEN=$((SEEN+1))
      shift 2
      ;;
    --dangerously-bypass-approvals-and-sandbox|--full-auto)
      echo "PILOT_GUARD: unrestricted flag rejected" >&2
      exit 45
      ;;
    *) ARGS+=("$1"); shift;;
  esac
done
[ "$SEEN" -eq 1 ] || { echo "PILOT_GUARD: expected one sandbox option" >&2; exit 46; }
echo "PILOT_GUARD: sandbox=workspace-write" >&2
exec env -u OPENAI_API_KEY -u CODEX_API_KEY "$REAL" "${ARGS[@]}"
