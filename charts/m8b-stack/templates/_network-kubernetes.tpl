{{/* Portable networking.k8s.io/v1 L3/L4 helpers; no Cilium types are rendered here. */}}
{{- define "stack.kubePorts" -}}
{{ range . }}
- port: {{ .port | int }}
  protocol: {{ .protocol }}
{{ if .endPort }}
  endPort: {{ .endPort }}
{{ end }}
{{ end }}
{{- end }}

{{- define "stack.kubeDns" -}}
- to:
    # Both selectors belong to ONE peer: namespace AND Pod labels.
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ .Values.network.dns.namespace | quote }}
      podSelector:
        matchLabels:
{{ toYaml .Values.network.dns.labels | indent 10 }}
  ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
{{ range .Values.network.dns.ipBlocks }}
- to:
    - ipBlock:
        cidr: {{ . | quote }}
  ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
{{ end }}
{{- end }}

{{- define "stack.kubeCidrEgress" -}}
{{ range . }}
- to:
    - ipBlock:
        cidr: {{ .cidr | quote }}
{{ with .except }}
        except:
{{ toYaml . | indent 10 }}
{{ end }}
{{ with .ports }}
  ports:
{{ include "stack.kubePorts" . | indent 4 }}
{{ end }}
{{ end }}
{{- end }}

{{- define "stack.kubePublicEgress" -}}
{{- $v := .root.Values -}}
{{- $rule := deepCopy $v.network.publicEgress -}}
{{- $_ := set $rule "except" (concat $rule.except $v.network.podCidrs $v.network.serviceCidrs | uniq | sortAlpha) -}}
{{- $_ := set $rule "ports" .ports -}}
{{ include "stack.kubeCidrEgress" (list $rule) }}
{{- end }}

{{- define "stack.kubePodEgress" -}}
{{ range . }}
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ .namespace | quote }}
      podSelector:
        matchLabels:
{{ toYaml .matchLabels | indent 10 }}
  ports:
{{ include "stack.kubePorts" .ports | indent 4 }}
{{ end }}
{{- end }}
