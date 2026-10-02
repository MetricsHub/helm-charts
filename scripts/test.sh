#!/usr/bin/env bash
# Offline chart checks: lint, render every stage/overlay, reject invalid values, script unit tests.
# Needs real Helm and Node.js. No cluster access.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v helm >/dev/null || { echo 'helm is required' >&2; exit 1; }

render() { helm template t "$@" --namespace ci >/dev/null; }

for chart in charts/*/; do
  helm lint "$chart" --strict
done

# m8b-stack: stages x example overlays, all on top of the portable site profile.
C=charts/m8b-stack
P="$C/examples/portable.yaml"
for stage in core check run index; do
  helm lint "$C" --strict -f "$P" --set stage="$stage"
  render "$C" -f "$P" --set stage="$stage"
  for overlay in "$C"/examples/*.yaml; do
    [ "$overlay" = "$P" ] && continue
    render "$C" -f "$P" -f "$overlay" --set stage="$stage"
  done
done
render "$C"                                                   # bare defaults (stage=core)
render "$C" -f "$P" --set stage=run --set storage.mode=local --set storage.local.node=node-a
render "$C" -f "$P" --set stage=run --set storage.mode=existing
render "$C" -f "$P" --set stage=run --set searxng.enabled=false

# Each of these MUST be rejected by 00-validate.yaml or values.schema.json.
reject() {
  if render "$C" -f "$P" "$@" 2>/dev/null; then echo "NOT rejected: $*" >&2; exit 1; fi
}
reject --set stage=run --set m8b.slackTeamId=
reject --set stage=run --set m8b.ai.model=
reject --set storage.mode=local
reject --set metricshub.exposure.enabled=true
reject --set metricshub.monitorKubernetesNodes.enabled=true
reject --set m8b.dataDir=/etc
reject --set 'm8b.extraEnv[0].name=SLACK_BOT_TOKEN' --set 'm8b.extraEnv[0].value=x'
reject --set 'metricshub.egress[0].cidr=10.0.0.0/8'             # contains portable podCidrs
reject --set 'metricshub.egress[0].cidr=10.96.0.10/32'          # inside portable serviceCidrs
reject --set names.agent=x                                      # removed kit value

# Overlap is accepted when excepted or explicitly reviewed.
render "$C" -f "$P" --set 'metricshub.egress[0].cidr=10.0.0.0/8' --set 'metricshub.egress[0].except={10.244.0.0/16,10.96.0.0/12}'
render "$C" -f "$P" --set 'metricshub.egress[0].cidr=10.0.0.0/8' --set network.allowClusterCIDROverlap=true

# Names derive from the release, so two releases never collide.
a=$(helm template one "$C" -f "$P" --set stage=check | grep -E '^  name:' | sort)
b=$(helm template two "$C" -f "$P" --set stage=check | grep -E '^  name:' | sort)
[ -z "$(comm -12 <(echo "$a") <(echo "$b"))" ] || { echo 'Resource names collide between releases' >&2; exit 1; }
helm template x "$C" -f "$P" --set fullnameOverride=custom | grep -q 'name: "custom-agent"'

node --test tests/*/*.test.cjs
echo 'All chart checks passed.'
