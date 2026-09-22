{{- define "notes-api.fullname" -}}
{{ .Release.Name }}-notes-api
{{- end -}}

{{- define "notes-api.labels" -}}
app.kubernetes.io/name: notes-api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "notes-api.postgresFullname" -}}
{{- if contains "postgresql" .Release.Name -}}
{{ .Release.Name }}
{{- else -}}
{{ .Release.Name }}-postgresql
{{- end -}}
{{- end -}}
