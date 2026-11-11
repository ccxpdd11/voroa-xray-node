#!/bin/sh
# Runtime wrapper (DEPLOY_MEMORY.md Sec.5 route A).
# - Downloads xray-core official release at runtime if no binary is present.
# - Generates config.json from env: PORT / UUID / WS_PATH / XHTTP_PATH / TRANSPORT.
# - Listens on $PORT (platform-assigned, never hardcoded).
# - Default transport: VLESS+WS+TLS (TLS is terminated by the platform edge).
#   Fallback rule: if WS is broken twice (400 / 101-then-drop / H2 downgrade),
#   redeploy with TRANSPORT=xhttp (VLESS+XHTTP packet-up + TLS, ALPN http/1.1).
# - UUID is NEVER written into this repo. Set it as a platform env var / secret,
#   and store the per-node value only in a local 600-permission credential file.
set -eu
PORT="${PORT:-8080}"
UUID="${UUID:-}"
WS_PATH="${WS_PATH:-/ws}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"
TRANSPORT="${TRANSPORT:-ws}"
XRAY_VERSION="${XRAY_VERSION:-v26.11.9}"
if [ -z "$UUID" ]; then echo "ERROR: UUID env var is required (set it in the platform dashboard, never in a file)" >&2; exit 1; fi
case "$UUID" in
  ????????-????-????-????-????????????) ;;
  *) echo "ERROR: UUID does not look like a UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)" >&2; exit 1 ;;
esac
case "$TRANSPORT" in ws|xhttp) ;; *) echo "ERROR: TRANSPORT must be ws or xhttp" >&2; exit 1 ;; esac
# Locate or download the xray binary.
XRAY_BIN=""
for cand in ./xray /usr/local/bin/xray /usr/bin/xray; do
  if [ -x "$cand" ]; then XRAY_BIN="$cand"; break; fi
done
if [ -z "$XRAY_BIN" ]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) PKG="Xray-linux-64.zip" ;;
    aarch64|arm64) PKG="Xray-linux-arm64-v8a.zip" ;;
    armv7l) PKG="Xray-linux-arm32-v7a.zip" ;;
    *) PKG="Xray-linux-64.zip" ;;
  esac
  URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${PKG}"
  echo "Downloading xray-core ${XRAY_VERSION} (${PKG}) ..."
  mkdir -p /tmp/xray-dl
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o /tmp/xray-dl/xray.zip "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/xray-dl/xray.zip "$URL"
  else echo "ERROR: need curl or wget to fetch xray-core" >&2; exit 1; fi
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q /tmp/xray-dl/xray.zip -d /tmp/xray-dl
  else
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/xray-dl/xray.zip').extractall('/tmp/xray-dl')"
  fi
  chmod +x /tmp/xray-dl/xray
  XRAY_BIN="/tmp/xray-dl/xray"
fi
echo "xray: $($XRAY_BIN version | head -n 1)"
# Generate config.json from env (no secrets are echoed).
if [ "$TRANSPORT" = "xhttp" ]; then
  STREAM="\"network\": \"xhttp\", \"xhttpSettings\": {\"path\": \"$XHTTP_PATH\", \"mode\": \"packet-up\"}"
  LISTEN_PATH="$XHTTP_PATH"
else
  STREAM="\"network\": \"ws\", \"wsSettings\": {\"path\": \"$WS_PATH\"}"
  LISTEN_PATH="$WS_PATH"
fi
cat > config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "flow": ""}], "decryption": "none"},
      "streamSettings": {$STREAM}
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF
echo "ready: transport=$TRANSPORT path=$LISTEN_PATH port=$PORT (TLS terminated by platform edge; force ALPN http/1.1 on the client when using xhttp)"
exec "$XRAY_BIN" -config config.json
