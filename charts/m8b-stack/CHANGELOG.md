# Changelog

## 2.1.0 (2026-10-03)

- M8B bot image 3.1.0 (`docker.metricshub.com/metricshub/m8b-slack:3.1.0`); `appVersion` 3.1.0.
- Knowledge-base errors name the Helm setting to use (`m8b.knowledgeBase.bootstrap.mode=always`) instead of kit commands.
- Documentation: GETTING-STARTED pins the chart version and checks both private images; README, KNOWLEDGE-BASE
  and NETWORK-POLICIES aligned with it (step numbers, Job retries, full list of allowed network flows).

## 2.0.0 (2026-10-02)

First release published from github.com/metricshub/helm-charts (Helm repository and GHCR OCI).
Breaking for installations made with the 1.5.0 kit: resource and PVC names change.

- Agent image switched to MetricsHub Enterprise (`docker.metricshub.com/metricshub-enterprise:3.9.07`). The agent
  pushes OTLP over loopback to its embedded OpenTelemetry Collector, which exports to Prometheus and exposes
  13133 (health) and 24375 (Prometheus exporter). New `metricshub.otel.configText` and `metricshub.otel.ingressCidrs`.
- Prometheus promotes OTLP resource attributes to labels (replaces the agent's `append_resource_attributes`).
- `m8b.allowSelfSignedMcp` defaults to `true`: the agent serves MCP with a self-signed certificate.
- Names follow Helm conventions (`fullname`, `nameOverride`, `fullnameOverride`); `names.*` removed. Selectors
  and labels use `app.kubernetes.io/{name,instance,component}` plus `helm.sh/chart`, `managed-by`, `version`.
  Local PV paths become `<basePath>/<namespace>/<fullname>/<component>`.
- Doctor and KB index Jobs are suffixed with the Helm revision, so re-running `check`/`index` works.
- `metricshub.egress` rules overlapping `network.podCidrs`/`serviceCidrs` are rejected unless excepted or
  `network.allowClusterCIDROverlap: true`.
- Removed kit-only values: `namespace`, `releaseName`, `names`, `secrets.mode`, `secrets.bootstrapUser`,
  `storage.keep`, `storage.local.prepareOnThisHost`, `metricshub.bootstrap`, `m8b.ai.requireApiKey`,
  `m8b.doctorOnStartup`, `operations`.
- README documents private registry access and the Enterprise/OTel architecture; `examples/portable.yaml`
  shows monitored networks and cluster CIDRs.

## 1.5.0

- Standard Kubernetes NetworkPolicies by default (`network.provider: kubernetes`); Cilium is opt-in.
- Generic CSI storage defaults; examples contain placeholders only.
- NOTES.txt prints the next step for the current stage; README documents the full staged sequence with plain Helm.
