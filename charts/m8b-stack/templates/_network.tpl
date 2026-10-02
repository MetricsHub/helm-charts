{{- define "stack.endpoint" -}}
matchLabels:
  m8b-stack.io/network-role: {{ .role | quote }}
  app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
{{- end }}

{{- define "stack.dns" -}}
toEndpoints:
  - matchLabels:
      k8s:io.kubernetes.pod.namespace: {{ .Values.network.dns.namespace | quote }}
{{ range $key, $value := .Values.network.dns.labels }}
      {{ printf "k8s:%s" $key }}: {{ $value | quote }}
{{ end }}
toPorts:
  - ports:
      - port: "53"
        protocol: UDP
      - port: "53"
        protocol: TCP
{{- end }}

{{- define "stack.ports" -}}
{{ range . }}
- port: {{ .port | toString | quote }}
  protocol: {{ .protocol }}
{{ if .endPort }}
  endPort: {{ .endPort }}
{{ end }}
{{ end }}
{{- end }}

{{- define "stack.cidrEgress" -}}
{{ range . }}
- toCIDRSet:
    - cidr: {{ .cidr | quote }}
{{ with .except }}
      except:
{{ toYaml . | indent 8 }}
{{ end }}
{{ with .ports }}
  toPorts:
    - ports:
{{ include "stack.ports" . | indent 8 }}
{{ end }}
{{ end }}
{{- end }}

{{- define "stack.publicEgress" -}}
{{- $v := .root.Values -}}
{{- $rule := deepCopy $v.network.publicEgress -}}
{{- $_ := set $rule "except" (concat $rule.except $v.network.podCidrs $v.network.serviceCidrs | uniq | sortAlpha) -}}
{{- $_ := set $rule "ports" .ports -}}
{{ include "stack.cidrEgress" (list $rule) }}
{{- end }}

{{- define "stack.extraDns" -}}
{{- range .Values.network.dns.ipBlocks }}
- toCIDRSet:
    - cidr: {{ . | quote }}
  toPorts:
    - ports:
        - port: "53"
          protocol: UDP
        - port: "53"
          protocol: TCP
{{- end }}
{{- end }}

{{- define "stack.podEgress" -}}
{{- range . }}
- toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: {{ .namespace | quote }}
{{ range $key, $value := .matchLabels }}
        {{ printf "k8s:%s" $key }}: {{ $value | quote }}
{{ end }}
  toPorts:
    - ports:
{{ include "stack.ports" .ports | indent 8 }}
{{- end }}
{{- end }}
