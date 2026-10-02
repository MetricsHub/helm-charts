{{- define "stack.m8bConfigBase" -}}
{{- $n := include "stack.names" . | fromYaml -}}
NODE_ENV: production
AI_PROVIDER: vllm
AI_BASE_URL: {{ trimSuffix "/" .Values.m8b.ai.baseUrl | quote }}
AI_MODEL: {{ .Values.m8b.ai.model | quote }}
M8B_START_DEGRADED: 'false'
MCP_AGENT_URL: {{ printf "https://%s.%s.svc.%s:31888/sse" $n.agent .Release.Namespace .Values.network.clusterDomain | quote }}
MCP_AGENT_TRANSPORT: sse
MCP_ALLOW_SELF_SIGNED_CERT: {{ toString .Values.m8b.allowSelfSignedMcp | quote }}
M8B_DATA_DIR: {{ .Values.m8b.dataDir | quote }}
AI_EMBEDDING_MODEL: {{ .Values.m8b.embeddings.model | quote }}
WEB_SEARCH_PROVIDER: {{ ternary "searxng" "" .Values.searxng.enabled | quote }}
SEARXNG_URL: {{ ternary (printf "http://%s:8080" $n.searxng) "" .Values.searxng.enabled | quote }}
FETCH_URL_ENABLED: {{ toString .Values.m8b.fetchUrlEnabled | quote }}
CODE_SANDBOX_ENABLED: {{ toString .Values.m8b.codeSandboxEnabled | quote }}
METRICSHUB_CONFIG_ADMINS: ''
M8B_PROMETHEUS_URL: {{ ternary (printf "http://%s:9090" $n.prometheus) "" .Values.m8b.enablePromql | quote }}
REQUIRE_METRICSHUB_METRICS: {{ toString .Values.checks.requireMetrics | quote }}
SEARCH_CHECK_QUERY: {{ .Values.checks.searchQuery | quote }}
CHECK_ATTEMPTS: {{ toString .Values.m8b.startupAttempts | quote }}
CHECK_RETRY_SECONDS: {{ toString .Values.m8b.startupRetrySeconds | quote }}
AI_EMBEDDING_BASE_URL: {{ trimSuffix "/" .Values.m8b.embeddings.baseUrl | quote }}
M8B_KB_BOOTSTRAP_MODE: {{ .Values.m8b.knowledgeBase.bootstrap.mode | quote }}
M8B_KB_EMPTY_POLICY: {{ .Values.m8b.knowledgeBase.bootstrap.emptyPolicy | quote }}
M8B_KB_TIMEOUT_SECONDS: {{ toString .Values.m8b.knowledgeBase.bootstrap.timeoutSeconds | quote }}
M8B_KB_SEED_CONFIGURED: {{ toString (not (empty .Values.m8b.knowledgeBase.seedConfigMap)) | quote }}
{{ with .Values.m8b.knowledgeBase.directory }}
KNOWLEDGE_BASE_DIR: {{ . | quote }}
{{ end }}
{{ range $key, $env := dict "queryPrefix" "AI_EMBEDDING_QUERY_PREFIX" "documentPrefix" "AI_EMBEDDING_DOCUMENT_PREFIX" "queryInputType" "AI_EMBEDDING_QUERY_INPUT_TYPE" "documentInputType" "AI_EMBEDDING_DOCUMENT_INPUT_TYPE" }}
{{ if ne (index $.Values.m8b.embeddings $key) nil }}
{{ $env }}: {{ index $.Values.m8b.embeddings $key | quote }}
{{ end }}{{ end }}
{{- end }}

{{- define "stack.m8bConfig" -}}
{{- $data := include "stack.m8bConfigBase" . | fromYaml -}}
{{- range $key, $value := .Values.m8b.extraConfig -}}
{{- if or (regexMatch "(?i)(TOKEN|PASSWORD|SECRET|API_KEY)|^M8B_KB_" $key) (has $key (list "M8B_START_DEGRADED" "AI_BASE_URL" "AI_MODEL" "MCP_AGENT_URL" "M8B_DATA_DIR" "AI_EMBEDDING_BASE_URL" "AI_EMBEDDING_MODEL" "CODE_SANDBOX_ENABLED" "FETCH_URL_ENABLED" "KNOWLEDGE_BASE_DIR" "AI_EMBEDDING_QUERY_PREFIX" "AI_EMBEDDING_DOCUMENT_PREFIX" "AI_EMBEDDING_QUERY_INPUT_TYPE" "AI_EMBEDDING_DOCUMENT_INPUT_TYPE")) }}{{ fail "Protected or secret field in m8b.extraConfig" }}{{ end -}}
{{- $_ := set $data $key $value -}}
{{- end -}}
{{ toYaml $data }}
{{- end }}
