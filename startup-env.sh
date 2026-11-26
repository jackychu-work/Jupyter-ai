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
