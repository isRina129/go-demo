#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <artifact.zip>" >&2
  exit 2
fi

artifact="$1"
: "${ARTIFACT_ID:?ARTIFACT_ID is required}"
: "${ARTIFACT_TOKEN:?ARTIFACT_TOKEN is required}"
: "${CREDENTIALS_URL:?CREDENTIALS_URL is required}"

if [[ ! -s "$artifact" ]]; then
  echo "artifact does not exist or is empty: $artifact" >&2
  exit 2
fi

credential_response="$(mktemp)"
ossutil_config="$(mktemp)"
cleanup() {
  rm -f "$credential_response" "$ossutil_config"
}
trap cleanup EXIT

curl --fail-with-body --silent --show-error \
  --retry 3 --retry-all-errors \
  -X POST \
  -H "Authorization: Bearer $ARTIFACT_TOKEN" \
  -H "Content-Type: application/json" \
  "$CREDENTIALS_URL" \
  > "$credential_response"

access_key_id="$(jq -r '.data.access_key_id' "$credential_response")"
access_key_secret="$(jq -r '.data.access_key_secret' "$credential_response")"
security_token="$(jq -r '.data.security_token' "$credential_response")"
region="$(jq -r '.data.region' "$credential_response")"
bucket="$(jq -r '.data.oss.bucket' "$credential_response")"
object_key="$(jq -r '.data.oss.object_key' "$credential_response")"

if [[ -z "$access_key_id" || "$access_key_id" == "null" ||
      -z "$access_key_secret" || "$access_key_secret" == "null" ||
      -z "$security_token" || "$security_token" == "null" ||
      -z "$region" || "$region" == "null" ||
      -z "$bucket" || "$bucket" == "null" ||
      -z "$object_key" || "$object_key" == "null" ||
      "$(jq -r '.data.artifact_type' "$credential_response")" != "ZIP" ]]; then
  echo "fc-devops returned incomplete STS credentials or OSS destination" >&2
  exit 1
fi

echo "::add-mask::$access_key_id"
echo "::add-mask::$access_key_secret"
echo "::add-mask::$security_token"

ossutil_version="${OSSUTIL_VERSION:-1.7.19}"
curl --fail --silent --show-error --retry 3 \
  "https://gosspublic.alicdn.com/ossutil/${ossutil_version}/ossutil64" \
  --output "$RUNNER_TEMP/ossutil"
chmod +x "$RUNNER_TEMP/ossutil"

"$RUNNER_TEMP/ossutil" config \
  -e "https://oss-${region}.aliyuncs.com" \
  -i "$access_key_id" \
  -k "$access_key_secret" \
  -t "$security_token" \
  -L CH \
  -c "$ossutil_config"

"$RUNNER_TEMP/ossutil" cp \
  "$artifact" "oss://$bucket/$object_key" \
  -f -c "$ossutil_config"

echo "uploaded artifact to oss://$bucket/$object_key"
