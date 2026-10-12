---
date_published: 1980-02-01
date_modified: 1980-02-01
canonical_url: https://metricshub.org/helm-charts/charts/m8b-stack/CHANGELOG.html
---

# Changelog

## 2.1.4 (2026-10-12)

- The OpenTelemetry Collector configuration can be edited, including from the MetricsHub Web UI. Until 2.1.3, `otel-config.yaml` was a read-only ConfigMap file: saving it from the Web UI failed (the agent saves atomically, through a temporary file renamed over the original, which cannot replace a mounted file) and left `otel-config.yaml.*.tmp` files behind.
- `/opt/metricshub/lib/otel` is now on the agent volume (subPath `otel`). `otel-config.yaml` is written there at first start from `metricshub.otel.configText` or the bundled config, then left to the user; `managed` mode rewrites it at every start. The collector and Java agent are copied from the image whenever they differ, since the image only ships an example configuration in `/opt/metricshub/defaults/otel`.

## 2.1.3 (2026-10-06)

- `/opt/metricshub/lib/connectors` is now on the agent volume (subPath `connectors`): custom connectors copied there survive restarts and upgrades. The bundled connectors are copied from the image at every start, so they follow image upgrades; add your own files, do not edit the bundled ones.

## 2.1.2 (2026-10-05)

- README, repository index and chart description explain what the stack is for: an AI assistant in Slack that answers from live MetricsHub data, Prometheus history, the MetricsHub documentation and web search.

## 2.1.1 (2026-10-05)

- Architecture diagram (`architecture.svg`) replaces the text diagram in the README, also on the site: embedded OTel Collector pushing to Prometheus, outbound Slack and LLM connections, stage Jobs, Secrets and network rules.

## 2.1.0 (2026-10-03)

- M8B bot image 3.1.0 (`docker.metricshub.com/metricshub/m8b-slack:3.1.0`); `appVersion` 3.1.0.
- Knowledge-base errors name the Helm setting to use (`m8b.knowledgeBase.bootstrap.mode=always`) instead of kit commands.
- Documentation: GETTING-STARTED pins the chart version and checks both private images; README, KNOWLEDGE-BASE and NETWORK-POLICIES aligned with it (step numbers, Job retries, full list of allowed network flows).
- Documentation links to the MetricsHub Agent docs (Enterprise on Docker, resource settings) and to the M8B Slack bot docs (Slack app creation, configuration reference, AI backends).

## 2.0.0 (2026-10-02)

First release published from github.com/metricshub/helm-charts (Helm repository and GHCR OCI). Breaking for installations made with the 1.5.0 kit: resource and PVC names change.

- Agent image switched to MetricsHub Enterprise (`docker.metricshub.com/metricshub-enterprise:3.9.07`). The agent pushes OTLP over loopback to its embedded OpenTelemetry Collector, which exports to Prometheus and exposes 13133 (health) and 24375 (Prometheus exporter). New `metricshub.otel.configText` and `metricshub.otel.ingressCidrs`.
- Prometheus promotes OTLP resource attributes to labels (replaces the agent's `append_resource_attributes`).
- `m8b.allowSelfSignedMcp` defaults to `true`: the agent serves MCP with a self-signed certificate.
- Names follow Helm conventions (`fullname`, `nameOverride`, `fullnameOverride`); `names.*` removed. Selectors and labels use `app.kubernetes.io/{name,instance,component}` plus `helm.sh/chart`, `managed-by`, `version`. Local PV paths become `<basePath>/<namespace>/<fullname>/<component>`.
- Doctor and KB index Jobs are suffixed with the Helm revision, so re-running `check`/`index` works.
- `metricshub.egress` rules overlapping `network.podCidrs`/`serviceCidrs` are rejected unless excepted or `network.allowClusterCIDROverlap: true`.
- Removed kit-only values: `namespace`, `releaseName`, `names`, `secrets.mode`, `secrets.bootstrapUser`, `storage.keep`, `storage.local.prepareOnThisHost`, `metricshub.bootstrap`, `m8b.ai.requireApiKey`, `m8b.doctorOnStartup`, `operations`.
- README documents private registry access and the Enterprise/OTel architecture; `examples/portable.yaml` shows monitored networks and cluster CIDRs.

## 1.5.0

- Standard Kubernetes NetworkPolicies by default (`network.provider: kubernetes`); Cilium is opt-in.
- Generic CSI storage defaults; examples contain placeholders only.
- NOTES.txt prints the next step for the current stage; README documents the full staged sequence with plain Helm.
