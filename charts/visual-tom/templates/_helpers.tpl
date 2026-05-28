{{/*
Expand the name of the chart.
*/}}
{{- define "vtom.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Deployment namespace.
*/}}
{{- define "vtom.namespace" -}}
{{- .Values.namespace | default "vtom" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "vtom.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Full image for a VTOM component (server / apiserver / agent).
Concatenates global.imageRegistry + repository + tag.
*/}}
{{- define "vtom.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repo := .Values.vtom.image.repository -}}
{{- $tag := .Values.vtom.image.tag | default .Chart.AppVersion -}}
{{- if $registry -}}
{{ $registry }}/{{ $repo }}:{{ $tag }}
{{- else -}}
{{ $repo }}:{{ $tag }}
{{- end }}
{{- end }}

{{/*
Full image for ITC.
*/}}
{{- define "itc.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repo := .Values.itc.image.repository -}}
{{- $tag := .Values.itc.image.tag | required "itc.image.tag is required when itc.enabled=true" -}}
{{- if $registry -}}
{{ $registry }}/{{ $repo }}:{{ $tag }}
{{- else -}}
{{ $repo }}:{{ $tag }}
{{- end }}
{{- end }}

{{/*
Full image for ITM.
*/}}
{{- define "itm.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repo := .Values.itm.image.repository -}}
{{- $tag := .Values.itm.image.tag | required "itm.image.tag is required when itm.enabled=true" -}}
{{- if $registry -}}
{{ $registry }}/{{ $repo }}:{{ $tag }}
{{- else -}}
{{ $repo }}:{{ $tag }}
{{- end }}
{{- end }}

{{/*
Full image for MFT.
*/}}
{{- define "mft.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" -}}
{{- $repo := .Values.mft.image.repository -}}
{{- $tag := .Values.mft.image.tag | required "mft.image.tag is required when mft.enabled=true" -}}
{{- if $registry -}}
{{ $registry }}/{{ $repo }}:{{ $tag }}
{{- else -}}
{{ $repo }}:{{ $tag }}
{{- end }}
{{- end }}

{{/*
Name of the vtom-server Service (= vtom.serverName).
Used as the pod hostname and as the Kubernetes Service name.
*/}}
{{- define "vtom.serverName" -}}
{{- .Values.vtom.serverName | default "vtom-server" }}
{{- end }}

{{/*
StorageClass for a PVC — uses the specific value or the global value.
Usage: {{ include "vtom.storageClass" .Values.vtom.serverPvc }}
*/}}
{{- define "vtom.storageClass" -}}
{{- if . -}}
storageClassName: {{ . }}
{{- end }}
{{- end }}

{{/*
imagePullSecrets — injects the list when defined.
*/}}
{{- define "vtom.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ .name }}
{{- end }}
{{- end }}
{{- end }}

{{/*
initContainer wait-for-db — waits until localhost:5432 is reachable.
Used only when dbProxy.enabled=true.
*/}}
{{- define "vtom.initContainer.waitForDb" -}}
- name: wait-for-db
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z 127.0.0.1 5432; do echo "Waiting for DB..."; sleep 2; done']
  resources:
    requests:
      cpu: "10m"
      memory: "16Mi"
    limits:
      cpu: "10m"
      memory: "16Mi"
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534  # nobody (busybox)
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
{{- end }}

{{/*
initContainer wait-for-server — waits until vtom-server is reachable
on its SSL port (svtserver). Used in deployments that depend on
the server (apiserver, agent).
*/}}
{{- define "vtom.initContainer.waitForServer" -}}
- name: wait-for-server
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z {{ include "vtom.serverName" . }} {{ .Values.vtom.ports.svtserver }}; do echo "Waiting for vtom-server..."; sleep 3; done']
  resources:
    requests:
      cpu: "10m"
      memory: "16Mi"
    limits:
      cpu: "10m"
      memory: "16Mi"
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534  # nobody (busybox)
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
{{- end }}

{{/*
initContainer wait-for-apiserver — waits until vtom-apiserver is
reachable on its HTTPS port. Used in deployments that depend on
the apiserver (ITC).
*/}}
{{- define "vtom.initContainer.waitForApiserver" -}}
- name: wait-for-apiserver
  image: busybox:1.36
  command: ['sh', '-c', 'until nc -z apiserver {{ .Values.vtom.ports.apiserver }}; do echo "Waiting for vtom-apiserver..."; sleep 3; done']
  resources:
    requests:
      cpu: "10m"
      memory: "16Mi"
    limits:
      cpu: "10m"
      memory: "16Mi"
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534  # nobody (busybox)
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
{{- end }}

{{/*
Sidecar DB proxy — socat or Cloud SQL Auth Proxy depending on dbProxy.type.
Rendered only when dbProxy.enabled=true.
*/}}
{{- define "vtom.sidecar.dbProxy" -}}
{{- if .Values.dbProxy.enabled }}
- name: db-proxy
  {{- if eq .Values.dbProxy.type "cloudsql-proxy" }}
  image: {{ .Values.dbProxy.cloudsqlProxy.image }}
  restartPolicy: Always
  args:
    - "--structured-logs"
    - "--port=5432"
    - "--private-ip"
    - {{ .Values.dbProxy.cloudsqlProxy.instanceConnectionName | quote }}
  resources:
    {{- toYaml .Values.dbProxy.cloudsqlProxy.resources | nindent 4 }}
  {{- else }}
  image: {{ .Values.dbProxy.socat.image }}
  restartPolicy: Always
  command:
    - socat
    - TCP-LISTEN:5432,fork,reuseaddr
    - TCP:{{ .Values.dbProxy.socat.target }}
  resources:
    {{- toYaml .Values.dbProxy.socat.resources | nindent 4 }}
  {{- end }}
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
{{- end }}
{{- end }}

{{/*
Name of the ESO SecretStore depending on the cloud provider.
Explicit fail if external-secrets is enabled without cloud configuration.
*/}}
{{- define "vtom.secretStoreName" -}}
{{- if eq .Values.secrets.provider "external-secrets" -}}
{{- if .Values.secrets.azure.keyVaultUrl -}}azure-key-vault
{{- else if .Values.secrets.aws.region -}}aws-secrets-manager
{{- else if .Values.secrets.gcp.projectId -}}gcp-secret-manager
{{- else -}}
{{- fail "secrets.provider is 'external-secrets' but no cloud backend is configured. Set one of: secrets.azure.keyVaultUrl, secrets.aws.region, or secrets.gcp.projectId." -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Workload Identity annotation on the pod depending on the cloud provider.
*/}}
{{- define "vtom.workloadIdentityPodLabel" -}}
{{- if and .Values.serviceAccount.workloadIdentity.enabled .Values.serviceAccount.azure.clientId }}
azure.workload.identity/use: "true"
{{- end }}
{{- end }}

{{/*
Name of the license proxy ConfigMap, when licenseProxy.host is set.
Returns an empty string when no proxy is configured.
*/}}
{{- define "vtom.licenseProxyConfigMapName" -}}
{{- if .Values.licenseProxy.host -}}
{{ include "vtom.name" . }}-license-proxy
{{- end -}}
{{- end }}
