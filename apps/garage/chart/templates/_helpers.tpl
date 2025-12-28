{{/*
Expand the name of the chart.
*/}}
{{- define "garage.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "garage.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "garage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "garage.labels" -}}
helm.sh/chart: {{ include "garage.chart" . }}
{{ include "garage.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "garage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "garage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "garage.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "garage.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the default garage.toml config
*/}}
{{- define "garage.toml" -}}
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "{{ .Values.garage.dbEngine }}"
block_size = {{ .Values.garage.blockSize }}
replication_mode = "{{ .Values.garage.replicationMode }}"
compression_level = {{ .Values.garage.compressionLevel }}

{{- if .Values.garage.metadataAutoSnapshotInterval }}
metadata_auto_snapshot_interval = "{{ .Values.garage.metadataAutoSnapshotInterval }}"
{{- end }}

[rpc]
bind_addr = "{{ .Values.garage.rpcBindAddr }}"
secret = "{{ .Values.garage.rpcSecret }}"
{{- if gt (len .Values.garage.bootstrapPeers) 0 }}
bootstrap_peers = [
{{- range .Values.garage.bootstrapPeers }}
"{{.}}",
{{- end }}
]
{{- end }}

[kubernetes_discovery]
namespace = "{{ .Release.Namespace }}"
service_name = "{{ include "garage.fullname" . }}-headless"
skip_crd = {{ .Values.garage.kubernetesSkipCrd }}

[s3_api]
s3_region = "{{ .Values.garage.s3.api.region }}"
root_domain = "{{ .Values.garage.s3.api.rootDomain }}"
api_bind_addr = "[::]:3900"

[s3_web]
root_domain = "{{ .Values.garage.s3.web.rootDomain }}"
index = "{{ .Values.garage.s3.web.index }}"
bind_addr = "[::]:3902"
{{- end }}

