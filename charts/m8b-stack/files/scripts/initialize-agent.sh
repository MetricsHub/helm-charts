#!/bin/sh
set -eu
mkdir -p /data/config /data/logs /data/security
if [ ! -e /data/.initialized ]; then
  existing_config=no
  [ ! -e /data/config/metricshub.yaml ] || existing_config=yes
  if [ -d /opt/metricshub/lib/config ]; then
    cp -Rn /opt/metricshub/lib/config/. /data/config/
  fi
  if [ "$existing_config" = no ]; then
    cp /bootstrap/metricshub.yaml /data/config/metricshub.yaml
  fi
  touch /data/.initialized
fi
if [ "${CONFIG_MODE:-seed}" = managed ]; then
  cp /bootstrap/metricshub.yaml /data/config/metricshub.yaml
fi
test -s /data/config/metricshub.yaml || { echo 'Persistent configuration missing; refusing silent reinitialization' >&2; exit 1; }
echo 'MetricsHub persistent configuration and security directory preserved.'
