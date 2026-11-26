#!/bin/bash
# Sourced by start.sh (docker-stacks hook directory), so these exports reach the
# notebook server and every child process — including the @OpenCode ACP persona,
# whose opencode.json resolves {env:OPENAI_API_BASE} / {env:OPENAI_API_KEY}.
#
# Deployment contract (unchanged from the documented setup): the operator writes
#   OPENAI_API_BASE=https://<gateway>/v1
#   OPENAI_API_KEY=<virtual key>
# to /home/jovyan/.env. Nothing is baked into the image.
if [ -f "${HOME}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${HOME}/.env"
    set +a
fi

if [ -z "${OPENAI_API_BASE:-}" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "WARNING: OPENAI_API_BASE / OPENAI_API_KEY not set; expected in ${HOME}/.env." >&2
    echo "         The @OpenCode persona will not reach a model until they are set." >&2
fi

# Optional private root CA: the deployment mounts one or more PEM certificates
# (not DER) under ${HOME}/.certs — mount them read-only if you like, nothing is
# written there. The merged bundle is written to ${HOME}/.ca-bundle.crt, outside
# the input directory, so repeated starts are idempotent and cannot truncate an
# input. Node/Bun (NODE_EXTRA_CA_CERTS), OpenSSL (SSL_CERT_FILE) and curl
# (CURL_CA_BUNDLE) all resolve the private root from it.
if [ -d "${HOME}/.certs" ] && ls "${HOME}"/.certs/*.crt >/dev/null 2>&1; then
    BUNDLE="${HOME}/.ca-bundle.crt"
    if cat /etc/ssl/certs/ca-certificates.crt "${HOME}"/.certs/*.crt > "${BUNDLE}"; then
        export NODE_EXTRA_CA_CERTS="${BUNDLE}"
        export SSL_CERT_FILE="${BUNDLE}"
        export CURL_CA_BUNDLE="${BUNDLE}"
        echo "Private CA bundle loaded: ${BUNDLE} ($(grep -c 'BEGIN CERTIFICATE' "${BUNDLE}") certificates)"
    else
        echo "WARNING: could not build the CA bundle from ${HOME}/.certs; continuing with the system store." >&2
    fi
fi
