{{/*
Reusable template snippets. `include "call-router.fullname" .` renders them.
*/}}

{{/* Resource name: <release>-call-router, max 63 chars (K8s limit). */}}
{{- define "call-router.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Selector labels: MUST stay stable, Deployments/Services match on them. */}}
{{- define "call-router.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Full label set: selector labels + informational labels. */}}
{{- define "call-router.labels" -}}
{{ include "call-router.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "call-router.serviceAccountName" -}}
{{- default (include "call-router.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}
