#!/usr/bin/env bash

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <OpenVPN Config File>"
  exit 1
fi

OPENVPN_CONFIG=$1

# Read proto, host, and port from the AWS-provided VPN config.
while read key value; do
  case ${key} in
  proto)
    PROTO=${value}
    ;;
  remote)
    # shellcheck disable=SC2206
    args=(${value})
    VPN_HOST=${args[0]}
    PORT=${args[1]}
    ;;

  esac
done <"${OPENVPN_CONFIG}"

echo "Connecting to host:${VPN_HOST} port:${PORT} proto:${PROTO}"

# path to the patched openvpn
OVPN_BIN="./openvpn"
# path to the configuration file
MODIFIED_CONFIG=$(mktemp)
trap 'rm -f ${MODIFIED_CONFIG}' EXIT
cp "${OPENVPN_CONFIG}" "${MODIFIED_CONFIG}"
sed -ri "/^auth-(federate|retry)/d" "${MODIFIED_CONFIG}"

# Sometimes AWS generates a file without an LF
echo >> "${MODIFIED_CONFIG}"

# Handle custom domain mappings since AWS can't.
if [ -f domains.txt ]; then
  CONFIG_NAME=${OPENVPN_CONFIG%.*}
  echo "CONFIG_NAME=$CONFIG_NAME"
  while read domain_name; do
    echo "Configuring DNS for domain ${domain_name}"
    echo "dhcp-option domain ${domain_name}" >>"${MODIFIED_CONFIG}"
  done <domains.txt
fi

# Support https://github.com/jonathanio/update-systemd-resolved/ to configure systemd-resolved DNS resolution
DNS_COMMAND="$(command -v update-systemd-resolved)"
if [ -x "${DNS_COMMAND}" ]; then
  {
    echo "setenv PATH /usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo "up ${DNS_COMMAND}"
    echo "up-restart"
    echo "down ${DNS_COMMAND}"
    echo "down-pre"
  } >>"${MODIFIED_CONFIG}"
else
  echo "Consider installing https://github.com/jonathanio/update-systemd-resolved/ if you use systemd-resolved."
fi

wait_file() {
  local file="$1"; shift
  local wait_seconds="${1:-10}"; shift # 10 seconds as default timeout
  until test $((wait_seconds--)) -eq 0 -o -f "$file" ; do sleep 1; done
  ((++wait_seconds))
}

# create random hostname prefix for the vpn gw
RAND=$(openssl rand -hex 12)

# resolv manually hostname to IP, as we have to keep persistent ip address
SRV=$(dig a +short "${RAND}.${VPN_HOST}"|head -n1)

# cleanup
rm -f saml-response.txt

echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})"
OVPN_OUT=$($OVPN_BIN --config "${MODIFIED_CONFIG}" --verb 3 \
  --connect-retry-max 3 \
  --connect-timeout 5 \
  --proto "${PROTO}" \
  --remote "${SRV}" "${PORT}" \
  --auth-user-pass fakecreds.txt \
  2>&1 | grep AUTH_FAILED,CRV1)

SERVER_PID=$(pgrep -f "go run server.go" || true)
if [ "${SERVER_PID}" == "" ]; then
  go run server.go &
  SERVER_PID=$!
fi
trap 'pkill -P ${SERVER_PID}' EXIT

echo "Opening browser and wait for the response file..."
URL=$(echo "${OVPN_OUT}" | grep -Eo 'https://.+')
trap 'rm -f saml-response.txt' EXIT
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     xdg-open "$URL";;
    Darwin*)    open "$URL";;
    *)          echo "Could not determine 'open' command for this OS"; exit 1;;
esac

wait_file "saml-response.txt" 30 || {
  echo "SAML Authentication time out"
  exit 1
}
pkill -P ${SERVER_PID}

# get SID from the reply
VPN_SID=$(echo "${OVPN_OUT}" | awk -F : '{print $7}')

printf '%s\n%s\n' "N/A" "CRV1::${VPN_SID}::$(cat saml-response.txt)" >"${SAML_CREDS:=$(mktemp)}"
trap 'rm -f ${SAML_CREDS}' EXIT
rm -f saml-response.txt

echo "Running OpenVPN with sudo. Enter password if requested"

# Finally OpenVPN with a SAML response we got
# Delete saml-response.txt after connect
sudo bash -c "$OVPN_BIN --config ${MODIFIED_CONFIG} \
    --verb 3 --auth-nocache --inactive 3600 \
    --proto $PROTO --remote $SRV $PORT \
    --script-security 2 \
    --route-up '/usr/bin/env rm ${SAML_CREDS}' \
    --auth-user-pass ${SAML_CREDS}"
