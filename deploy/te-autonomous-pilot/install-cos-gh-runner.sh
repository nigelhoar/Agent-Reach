#!/usr/bin/env bash
# Register one repository-scoped, self-hosted Actions control runner.
# Called as root through Azure VM RunCommand. The short-lived registration
# token must be supplied by Cloud Shell and never printed.
set -euo pipefail
H=/home/tepilot
RUNNER="$H/te-cos-actions-runner"
REPO="nigelhoar/te-chief-of-staff-ops"
NAME="te-cos-dev-uksouth"
test "$(id -un)" = root
test "$(id -un tepilot)" = tepilot
test -d "$H"
test -n "${COS_GH_RUNNER_TOKEN:-}" || { echo "Missing ephemeral registration token"; exit 1; }
systemctl is-active --quiet te-ai-pilot-block-imds.service
iptables -C OUTPUT -m owner --uid-owner tepilot -d 169.254.169.254 -j REJECT

if [ -f "$RUNNER/.runner" ]; then
  echo "COS_GITHUB_RUNNER=ALREADY_CONFIGURED"
  exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=x64; SHA=baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40;;
  aarch64) ARCH=arm64; SHA=670adb2f268fe21dcbb58b3db0e0aa9d5b3bddfe2c651481336e561ff86de945;;
  *) echo "Unsupported runner architecture"; exit 1;;
esac
VER=2.338.2
URL="https://github.com/actions/runner/releases/download/v$VER/actions-runner-linux-$ARCH-$VER.tar.gz"
install -d -m 0700 -o tepilot -g tepilot "$RUNNER"
cd "$RUNNER"
if [ ! -f ./config.sh ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL --retry 3 "$URL" -o "$TMP/runner.tar.gz"
  printf '%s  %s\n' "$SHA" "$TMP/runner.tar.gz" | sha256sum -c -
  tar -xzf "$TMP/runner.tar.gz" -C "$RUNNER"
  chown -R tepilot:tepilot "$RUNNER"
fi

# config.sh refuses root: execute as tepilot from its accessible home.
(
  cd "$RUNNER"
  runuser -u tepilot -- env HOME="$H" \
    ./config.sh --unattended \
    --url "https://github.com/$REPO" \
    --token "$COS_GH_RUNNER_TOKEN" \
    --name "$NAME" \
    --labels "te-cos-control" \
    --work "_work" \
    --disableupdate
)
unset COS_GH_RUNNER_TOKEN
./svc.sh install tepilot
./svc.sh start
echo "COS_GITHUB_RUNNER=REGISTERED"
echo "COS_RUNNER_SERVICE=STARTED"
echo "COS_REPOSITORY=$REPO"
echo "COS_RUNNER_LABEL=te-cos-control"

# Permit only one named service restart. Never grant unrestricted sudo.
cat >/etc/sudoers.d/te-cos-paperclip <<'SUDO'
tepilot ALL=(root) NOPASSWD: /usr/bin/systemctl restart te-paperclip-cos.service
SUDO
chmod 0440 /etc/sudoers.d/te-cos-paperclip
visudo -cf /etc/sudoers.d/te-cos-paperclip >/dev/null
echo "COS_RESTART_PRIVILEGE=SCOPED_TO_PAPERCLIP"
