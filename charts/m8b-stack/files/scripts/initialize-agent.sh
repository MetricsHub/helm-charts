#!/bin/sh
set -eu
mkdir -p /data/config /data/logs /data/security /data/connectors /data/otel
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
# Connectors live on the volume so that files added there survive restarts. The image's own connectors are
# copied over at every start: an image upgrade updates them. Add your own files; bundled ones are overwritten.
cp -R /opt/metricshub/lib/connectors/. /data/connectors/
# Embedded OpenTelemetry Collector: its folder lives on the volume so that otel-config.yaml can be edited there,
# and rewritten by the agent. The image's files (collector, Java agent) are copied when they differ.
for f in /opt/metricshub/lib/otel/*; do
  [ -f "$f" ] && [ "${f##*/}" != otel-config.yaml ] || continue
  cmp -s "$f" "/data/otel/${f##*/}" || cp -p "$f" /data/otel/
done
# otel-config.yaml: written once from the chart, then yours to edit (managed mode rewrites it at every start).
if [ ! -e /data/otel/otel-config.yaml ] || [ "${CONFIG_MODE:-seed}" = managed ]; then
  cp /otel-seed/otel-config.yaml /data/otel/otel-config.yaml
fi
test -s /data/config/metricshub.yaml || { echo 'Persistent configuration missing; refusing silent reinitialization' >&2; exit 1; }
echo 'MetricsHub persistent configuration and security directory preserved.'
