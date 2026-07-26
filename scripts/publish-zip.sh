#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <artifact.zip>" >&2
  exit 2
fi

artifact="$1"
: "${FC_DEVOPS_API_URL:?FC_DEVOPS_API_URL is required}"
: "${RELEASE_ID:?RELEASE_ID is required}"
: "${CALLBACK_TOKEN:?CALLBACK_TOKEN is required}"

if [[ ! -s "$artifact" ]]; then
  echo "artifact does not exist or is empty: $artifact" >&2
  exit 2
fi

api_url="${FC_DEVOPS_API_URL%/}"
upload_response="$(mktemp)"
upload_headers="$(mktemp)"
cleanup() {
  rm -f "$upload_response" "$upload_headers"
}
trap cleanup EXIT

curl --fail-with-body --silent --show-error \
  --retry 3 --retry-all-errors \
  -X POST \
  -H "Authorization: Bearer $CALLBACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content_type":"application/zip"}' \
  "$api_url/api/v1/releases/$RELEASE_ID/artifacts/upload-url" \
  > "$upload_response"

bucket="$(jq -r '.data.bucket' "$upload_response")"
object_key="$(jq -r '.data.object_key' "$upload_response")"
method="$(jq -r '.data.method' "$upload_response")"
upload_url="$(jq -r '.data.url' "$upload_response")"

if [[ -z "$bucket" || "$bucket" == "null" || -z "$object_key" || "$object_key" == "null" || -z "$upload_url" || "$upload_url" == "null" ]]; then
  echo "fc-devops returned an incomplete upload response" >&2
  exit 1
fi

curl_args=()
while IFS= read -r header; do
  key="$(jq -r '.key' <<< "$header")"
  value="$(jq -r '.value' <<< "$header")"
  curl_args+=(-H "$key: $value")
done < <(jq -c '.data.headers | to_entries[]' "$upload_response")

curl --fail-with-body --silent --show-error \
  --retry 3 --retry-all-errors \
  -D "$upload_headers" \
  -X "$method" \
  "${curl_args[@]}" \
  --upload-file "$artifact" \
  "$upload_url" \
  > /dev/null

etag="$(awk 'tolower($1) == "etag:" {value=$2; gsub(/\\r|"/, "", value); print value}' "$upload_headers" | tail -n 1)"
if [[ -z "$etag" ]]; then
  echo "OSS upload response did not include an ETag" >&2
  exit 1
fi

sha256="$(sha256sum "$artifact" | awk '{print $1}')"
size_bytes="$(stat -c '%s' "$artifact")"
complete_payload="$(jq -n \
  --arg bucket "$bucket" \
  --arg object_key "$object_key" \
  --arg etag "$etag" \
  --arg sha256 "$sha256" \
  --argjson size_bytes "$size_bytes" \
  '{bucket:$bucket,object_key:$object_key,etag:$etag,sha256:$sha256,size_bytes:$size_bytes}')"

curl --fail-with-body --silent --show-error \
  --retry 3 --retry-all-errors \
  -X POST \
  -H "Authorization: Bearer $CALLBACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$complete_payload" \
  "$api_url/api/v1/releases/$RELEASE_ID/artifacts/complete"

