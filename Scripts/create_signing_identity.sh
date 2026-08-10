#!/bin/bash
# One-time setup: creates a local self-signed code-signing certificate so
# Scripts/build_app.sh can sign ClaudeUsageBar with a stable identity instead
# of ad-hoc (`codesign --sign -`). Ad-hoc-signed apps have no stable Team ID,
# so macOS can't durably remember "Always Allow" Keychain-access decisions
# across relaunches, which is why the app kept re-prompting for the login
# password. A fixed local identity fixes that permanently.
#
# Trusting the certificate (the `security add-trusted-cert` step below) will
# prompt for your macOS login password once — that's expected.
#
# Safe to re-run: skips creation if the identity already exists.
set -euo pipefail

CERT_NAME="ClaudeUsageBar Local Signing"

if security find-identity -v -p codesigning | grep -q "${CERT_NAME}"; then
    echo "Signing identity '${CERT_NAME}' already exists, nothing to do."
    exit 0
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "${WORKDIR}"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "${WORKDIR}/codesign.key" -out "${WORKDIR}/codesign.crt" \
    -days 3650 -nodes -subj "/CN=${CERT_NAME}" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature"

IMPORT_PASSWORD=$(openssl rand -hex 16)
openssl pkcs12 -export -out "${WORKDIR}/codesign.p12" \
    -inkey "${WORKDIR}/codesign.key" -in "${WORKDIR}/codesign.crt" \
    -passout "pass:${IMPORT_PASSWORD}"

security import "${WORKDIR}/codesign.p12" -k ~/Library/Keychains/login.keychain-db \
    -P "${IMPORT_PASSWORD}" -T /usr/bin/codesign -T /usr/bin/security

echo "Trusting the certificate for code signing (this will prompt for your login password)..."
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "${WORKDIR}/codesign.crt"

echo "Done. '${CERT_NAME}' is now a trusted local code-signing identity."
