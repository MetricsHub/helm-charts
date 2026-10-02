{{/* Small reusable helpers; resources remain explicit YAML in templates/*.yaml. */}}

{{/* ponytail: truncated to 40 so every "<fullname>-<suffix>" stays a valid 63-char DNS label. */}}
{{- define "stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 40 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- else -}}{{- printf "%s-%s" .Release.Name $name | trunc 40 | trimSuffix "-" -}}{{- end -}}
{{- end -}}
{{- end }}

{{/* Every resource name, derived from the release. Usage: $n := include "stack.names" . | fromYaml */}}
{{- define "stack.names" -}}
{{- $f := include "stack.fullname" . -}}
agent: {{ $f }}-agent
agentConfig: {{ $f }}-agent-bootstrap
otelConfig: {{ $f }}-agent-otel
agentLan: {{ $f }}-agent-lan
agentClaim: {{ $f }}-agent-data
prometheus: {{ $f }}-prometheus
prometheusConfig: {{ $f }}-prometheus-config
prometheusLan: {{ $f }}-prometheus-lan
prometheusClaim: {{ $f }}-prometheus-data
searxng: {{ $f }}-searxng
searxngConfig: {{ $f }}-searxng-config
bot: {{ $f }}-bot
botConfig: {{ $f }}-bot-config
botScripts: {{ $f }}-bot-scripts
botClaim: {{ $f }}-bot-data
{{/* Revision suffix: each upgrade creates a new Job; Helm deletes the previous one (Job specs are immutable). */}}
doctor: {{ $f }}-doctor-{{ .Release.Revision }}
kbIndex: {{ $f }}-kb-index-{{ .Release.Revision }}
{{- end }}

{{- define "stack.selectorLabels" -}}
app.kubernetes.io/name: {{ default .root.Chart.Name .root.Values.nameOverride | quote }}
app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
app.kubernetes.io/component: {{ .component | quote }}
{{- end }}

{{- define "stack.labels" -}}
{{ include "stack.selectorLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | quote }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service | quote }}
app.kubernetes.io/part-of: m8b-stack
{{ if .role }}m8b-stack.io/network-role: {{ .role | quote }}
{{ end }}
{{- end }}

{{- define "stack.placement" -}}
{{- $v := .root.Values -}}
{{- $p := index $v .component -}}
{{- $node := deepCopy $p.nodeSelector -}}
{{- if and (eq $v.storage.mode "local") .pvc -}}
{{- $_ := set $node "kubernetes.io/hostname" $v.storage.local.node -}}
{{- end -}}
imagePullSecrets:
  - name: {{ $v.secrets.registry | quote }}
{{ if $node }}nodeSelector:
{{ toYaml $node | indent 2 }}
{{ end }}{{ with $p.tolerations }}tolerations:
{{ toYaml . | indent 2 }}
{{ end }}{{ with $p.affinity }}affinity:
{{ toYaml . | indent 2 }}
{{ end }}
{{- end }}

{{- define "stack.agentConfig" -}}
{{- $n := include "stack.names" . | fromYaml -}}
{{- if .Values.metricshub.config.text -}}
{{ .Values.metricshub.config.text }}
{{- else -}}
# First-start seed. The agent pushes to the embedded OpenTelemetry Collector (same Pod, loopback only).
# osCommand observes the container, not the node.
otel:
  otel.exporter.otlp.metrics.endpoint: http://localhost:4317
  otel.exporter.otlp.metrics.protocol: grpc
resources:
  {{ $n.agent }}:
    attributes:
      host.name: {{ $n.agent }}
      host.type: linux
    protocols:
      osCommand:
        timeout: 120
{{ end -}}
{{- end }}

{{- define "stack.otelConfig" -}}
{{- if .Values.metricshub.otel.configText -}}{{ .Values.metricshub.otel.configText }}
{{- else -}}{{ tpl (.Files.Get "files/config/otel-config.yaml") . }}{{- end -}}
{{- end }}

{{- define "stack.promConfig" -}}
{{- if .Values.prometheus.configText -}}{{ .Values.prometheus.configText }}
{{- else -}}{{ .Files.Get "files/config/prometheus.yaml" }}{{- end -}}
{{- end }}

{{- define "stack.searxConfig" -}}
{{- if .Values.searxng.configText -}}{{ .Values.searxng.configText }}
{{- else -}}{{ .Files.Get "files/config/searxng.yaml" }}{{- end -}}
{{- end }}

{{/* Chomping preserves an explicitly empty string and embedded newlines. */}}
{{- define "stack.literal" -}}
{{- if hasSuffix "\n\n" . }}|+
{{ else if hasSuffix "\n" . }}|
{{ else }}|-
{{ end }}{{ trimSuffix "\n" . | indent 2 }}
{{- end }}

{{- define "stack.scriptData" -}}
{{- range $name := list "verify-workspace.js" "integration-checks.js" "retry-check.sh" "kb-bootstrap.cjs" }}
{{ $name }}: |
{{ $.Files.Get (printf "files/scripts/%s" $name) | trimSuffix "\n" | indent 2 }}
{{ end -}}
{{- end }}

{{- define "stack.componentHash" -}}
{{- if eq .component "prometheus" -}}{{ include "stack.promConfig" .root | sha256sum }}
{{- else if eq .component "metricshub" -}}
{{- $agent := ternary (include "stack.agentConfig" .root) (.root.Files.Get "files/scripts/initialize-agent.sh") (eq .root.Values.metricshub.config.mode "managed") -}}
{{- printf "%s\n%s" $agent (include "stack.otelConfig" .root) | sha256sum -}}
{{- else if eq .component "searxng" -}}{{ include "stack.searxConfig" .root | sha256sum }}
{{- else -}}
{{- dict "config" (include "stack.m8bConfig" .root | fromYaml) "workspace" .root.Values.m8b.slackTeamId "scripts" (include "stack.scriptData" .root | fromYaml) | toJson | sha256sum -}}
{{- end -}}
{{- end }}

{{/* IPv4 CIDR arithmetic for validation (sprig has none). "a.b.c.d/n" -> {"ip": int, "len": n} */}}
{{- define "stack.cidrParse" -}}
{{- $p := splitList "/" . -}}
{{- $o := splitList "." (first $p) -}}
{{- $ip := add (mul (atoi (index $o 0)) 16777216) (mul (atoi (index $o 1)) 65536) (mul (atoi (index $o 2)) 256) (atoi (index $o 3)) -}}
{{- dict "ip" $ip "len" (ternary (atoi (last $p)) 32 (eq (len $p) 2)) | toJson -}}
{{- end }}

{{/* "true" when CIDR (index . 0) contains CIDR (index . 1). */}}
{{- define "stack.cidrContains" -}}
{{- $a := include "stack.cidrParse" (index . 0) | fromJson -}}
{{- $b := include "stack.cidrParse" (index . 1) | fromJson -}}
{{- if le (int $a.len) (int $b.len) -}}
{{- $block := 1 -}}
{{- range until (sub 32 (int $a.len) | int) }}{{ $block = mul $block 2 }}{{ end -}}
{{- if eq (div (int64 $a.ip) $block) (div (int64 $b.ip) $block) }}true{{ end -}}
{{- end -}}
{{- end }}
