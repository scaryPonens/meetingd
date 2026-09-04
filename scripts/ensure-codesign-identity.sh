#!/usr/bin/env bash
# Create or reuse a local code-signing identity so TCC can bind Accessibility to a
# stable certificate instead of an ad-hoc cdhash.
set -euo pipefail

IDENTITY="${MEETINGD_CODESIGN_IDENTITY:-meetingd Development}"

if security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null 2>&1; then
  echo "$IDENTITY"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/codesign.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = extensions

[req_distinguished_name]
CN = meetingd Development
O = meetingd
C = US

[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$TMP/meetingd.key" \
  -out "$TMP/meetingd.csr" \
  -config "$TMP/codesign.cnf" >/dev/null 2>&1

openssl x509 -req -days 3650 \
  -in "$TMP/meetingd.csr" \
  -signkey "$TMP/meetingd.key" \
  -out "$TMP/meetingd.crt" \
  -extfile "$TMP/codesign.cnf" \
  -extensions extensions >/dev/null 2>&1

openssl pkcs12 -export \
  -out "$TMP/meetingd.p12" \
  -inkey "$TMP/meetingd.key" \
  -in "$TMP/meetingd.crt" \
  -passout pass:meetingd >/dev/null 2>&1

security import "$TMP/meetingd.p12" \
  -k ~/Library/Keychains/login.keychain-db \
  -P meetingd \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null 2>&1 || true

# Allow codesign to use the key without interactive prompts in this login session.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || true

if ! security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null 2>&1; then
  echo "ad-hoc" >&2
  echo "-" 
  exit 0
fi

echo "$IDENTITY"
