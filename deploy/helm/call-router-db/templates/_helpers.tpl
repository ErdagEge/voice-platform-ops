{{- define "call-router-db.labels" -}}
app.kubernetes.io/name: call-router-db
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
{{- define "call-router-db.objectStore" -}}{{ .Values.name }}-backups{{- end }}
