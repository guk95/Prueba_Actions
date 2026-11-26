#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

zip_file="${1:?Indica la ruta al ZIP verificado.}"
: "${AMPLIFY_APP_ID:?Configura AMPLIFY_APP_ID.}"
: "${AMPLIFY_BRANCH_NAME:?Configura AMPLIFY_BRANCH_NAME.}"
: "${AMPLIFY_SITE_URL:?Configura AMPLIFY_SITE_URL.}"

[[ -s "$zip_file" ]] || fail 'El ZIP no existe o está vacío.'
[[ "$AMPLIFY_SITE_URL" =~ ^https://[^/?#@[:space:]]+(/[^?#[:space:]]*)?$ ]] ||
  fail 'AMPLIFY_SITE_URL debe ser una URL HTTPS sin credenciales ni parámetros.'

deployment=$(aws amplify create-deployment --no-cli-pager --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH_NAME" --query '[jobId, zipUploadUrl]' --output text)
IFS=$'\t' read -r job_id upload_url <<< "$deployment"
[[ "$job_id" =~ ^[0-9]+$ && "$upload_url" =~ ^https://[^\"\\[:space:]]+$ ]] ||
  fail 'Amplify devolvió una respuesta de creación inesperada.'

# Pasa la URL firmada por stdin y descarta el cuerpo de respuesta.
http_code=$(printf 'url = "%s"\n' "$upload_url" |
  curl --disable --config - --proto '=https' --globoff --silent --fail \
    --connect-timeout 10 --max-time 120 --retry 2 --retry-max-time 150 \
    --upload-file "$zip_file" --output /dev/null --write-out '%{http_code}') ||
  fail 'Falló la carga del ZIP a Amplify.'
unset deployment upload_url
[[ "$http_code" == 2[0-9][0-9] ]] || fail 'La carga del ZIP no devolvió HTTP 2xx.'

aws amplify start-deployment --no-cli-pager --app-id "$AMPLIFY_APP_ID" \
  --branch-name "$AMPLIFY_BRANCH_NAME" --job-id "$job_id" >/dev/null

deployed=false
for ((attempt = 1; attempt <= 60; attempt++)); do
  status=$(aws amplify get-job --no-cli-pager --app-id "$AMPLIFY_APP_ID" \
    --branch-name "$AMPLIFY_BRANCH_NAME" --job-id "$job_id" \
    --query 'job.summary.status' --output text)
  case "$status" in
    SUCCEED) deployed=true; break ;;
    CREATED|PENDING|PROVISIONING|RUNNING|CANCELLING) sleep 10 ;;
    FAILED|CANCELLED) fail "Amplify terminó con estado $status." ;;
    *) fail 'Amplify devolvió un estado inesperado.' ;;
  esac
done
[[ "$deployed" == true ]] || fail 'Se agotó el tiempo de espera del despliegue.'
printf '%s\n' 'Amplify confirmó el despliegue.'

for ((attempt = 1; attempt <= 6; attempt++)); do
  if http_code=$(curl --disable --proto '=https' --proto-redir '=https' --globoff \
    --silent --fail --location --max-redirs 5 --connect-timeout 5 --max-time 15 \
    --output /dev/null --write-out '%{http_code}' -- "$AMPLIFY_SITE_URL") &&
    [[ "$http_code" == 2[0-9][0-9] ]]; then
    printf 'Sitio publicado disponible (HTTP %s).\n' "$http_code"
    exit 0
  fi
  sleep 5
done
fail 'El sitio publicado no respondió con HTTP 2xx.'
