#!/usr/bin/env bash
set -e
. ./env

# Build binary

_ARGS=$@
"${WATCOM_BIN_DIR}/wmake" ${_ARGS}
