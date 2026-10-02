#!/bin/sh
set -eu
attempt=1
while [ "$attempt" -le "${CHECK_ATTEMPTS:-6}" ]; do
  if [ "$1" = integrations ]; then
    if node /stack-scripts/integration-checks.js; then exit 0; fi
  elif [ "$1" = doctor ]; then
    if node /app/scripts/doctor.js; then exit 0; fi
  else
    echo 'Unknown check' >&2; exit 2
  fi
  [ "$attempt" -lt "${CHECK_ATTEMPTS:-6}" ] || break
  echo "Check attempt $attempt failed; bounded retry." >&2
  sleep "${CHECK_RETRY_SECONDS:-10}"
  attempt=$((attempt + 1))
done
echo 'Check failed: application startup remains blocked.' >&2
exit 1
