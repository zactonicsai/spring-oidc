{{/*
Helpers. Several take a list: (list $root $svcName) so they can be used inside `range`.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{/* <app>-<service>  e.g. python-demo-web */}}
{{- define "app.svcname" -}}
{{- $root := index . 0 -}}{{- $svc := index . 1 -}}
{{- printf "%s-%s" (include "app.name" $root) $svc | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Labels used in selectors — MUST stay stable for the life of a Deployment */}}
{{- define "app.selectorLabels" -}}
{{- $root := index . 0 -}}{{- $svc := index . 1 -}}
app.kubernetes.io/name: {{ include "app.name" $root }}
app.kubernetes.io/component: {{ $svc }}
{{- end -}}

{{/* Full label set */}}
{{- define "app.labels" -}}
{{- $root := index . 0 -}}{{- $svc := index . 1 -}}
{{ include "app.selectorLabels" . }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/version: {{ $root.Values.version | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/part-of: {{ include "app.name" $root }}
helm.sh/chart: {{ printf "%s-%s" $root.Chart.Name $root.Chart.Version }}
{{- range $k, $v := $root.Values.global.labels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/* registry/repository:tag */}}
{{- define "app.image" -}}
{{- $root := index . 0 -}}{{- $svc := index . 1 -}}
{{- $reg := $root.Values.global.imageRegistry -}}
{{- $tag := default $root.Values.version $svc.image.tag -}}
{{- if $reg }}{{ $reg }}/{{ end }}{{ $svc.image.repository }}:{{ $tag }}
{{- end -}}

{{/* "true" if any port of the service is expose: public */}}
{{- define "app.isPublic" -}}
{{- $public := false -}}
{{- range .ports }}{{ if eq (default "cluster" .expose) "public" }}{{ $public = true }}{{ end }}{{ end -}}
{{- $public -}}
{{- end -}}
