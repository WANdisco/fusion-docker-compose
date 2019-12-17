#!/bin/sh

# Copyright: Brandon Mitchell
# License: MIT

# Purpose: Source an .env files, run any .sh files under $dir
# Usage: ./entrypointd.sh
set -e

dir="/etc/entrypoint.d"
for ep in $dir/*; do
  ext="${ep##*.}"
  if [ "${ext}" = "env" -a -f "${ep}" ]; then
    # source files ending in ".env"
    echo "Sourcing: ${ep}"
    set -a && . "${ep}" && set +a
  elif [ "${ext}" = "sh" -a -x "${ep}" ]; then
    # run scripts ending in ".sh"
    echo "Running: ${ep}"
    "${ep}"
  fi
done

# run a shell if there is no command passed
if [ $# = 0 ]; then
  if [ -x /bin/bash ]; then
    set -- /bin/bash
  else
    set -- /bin/sh
  fi
fi

# include tini if requested
if [ -n "${USE_INIT}" ]; then
  set -- tini -- "$@"
fi

# run command with exec to pass control
echo "Running CMD: $@"
exec "$@"
