{{/*
Chart name and version.
*/}}
{{- define "micros-02.chart" -}}
{{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "micros-02.labels" -}}
helm.sh/chart: {{ include "micros-02.chart" . }}
app.kubernetes.io/part-of: micros-02-two-services-over-http
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Catalog resource names.
*/}}
{{- define "micros-02.catalogName" -}}
{{ printf "%s-catalog-service" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "micros-02.catalogDbName" -}}
{{ printf "%s-catalog-service-db" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Pricing resource names.
*/}}
{{- define "micros-02.pricingName" -}}
{{ printf "%s-pricing-service" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "micros-02.pricingDbName" -}}
{{ printf "%s-pricing-service-db" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}