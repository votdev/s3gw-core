#!/bin/bash
# generate-spec.sh - create spec files for a k3s cluster with longhorn and s3gw
# Copyright 2022 SUSE, LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

tgtfile="s3gw.yaml"
is_dev_env=false

s3gw_image="ghcr.io/aquarist-labs/s3gw:latest"
s3gw_image_pull_policy="Always"

ingress="nginx"

while [[ $# -gt 0 ]]; do
  case $1 in
    --output|-o)
      tgtfile="${2}"
      shift 1
      ;;
    --dev)
      s3gw_image="localhost/s3gw:latest"
      s3gw_image_pull_policy="Never"
      ;;
    --traefik)
      ingress="traefik"
      ;;
    --nginx)
      ingress="nginx"
      ;;
  esac
  shift 1
done

s3gw_image=$(printf '%s\n' "$s3gw_image" | sed -e 's/[]\/$*.^[]/\\&/g')

sed "s/##S3GW_IMAGE##/"${s3gw_image}"/" s3gw/s3gw-deployment.yaml > s3gw/s3gw-deployment.tmp.yaml
sed -i "s/##S3GW_IMAGE_PULL_POLICY##/"${s3gw_image_pull_policy}"/" s3gw/s3gw-deployment.tmp.yaml

rgw_default_user_access_key_base64=$(cat s3gw/s3gw-secret.yaml | grep RGW_DEFAULT_USER_ACCESS_KEY | cut -d':' -f 2 | sed -e 's/[[:space:],"]//g')
rgw_default_user_access_key_base64=$(echo -n $rgw_default_user_access_key_base64 | base64)
rgw_default_user_access_key_base64=$(printf '%s\n' "$rgw_default_user_access_key_base64" | sed -e 's/[]\/$*.^[]/\\&/g')
rgw_default_user_secret_key_base64=$(cat s3gw/s3gw-secret.yaml | grep RGW_DEFAULT_USER_SECRET_KEY | cut -d':' -f 2 | sed -e 's/[[:space:],"]//g')
rgw_default_user_secret_key_base64=$(echo -n $rgw_default_user_secret_key_base64 | base64)
rgw_default_user_secret_key_base64=$(printf '%s\n' "$rgw_default_user_secret_key_base64" | sed -e 's/[]\/$*.^[]/\\&/g')

sed "s/##RGW_DEFAULT_USER_ACCESS_KEY_BASE64##/"\"${rgw_default_user_access_key_base64}\""/" s3gw/longhorn-s3gw-secret.yaml > s3gw/longhorn-s3gw-secret.tmp.yaml
sed -i "s/##RGW_DEFAULT_USER_SECRET_KEY_BASE64##/\""${rgw_default_user_secret_key_base64}\""/" s3gw/longhorn-s3gw-secret.tmp.yaml

[[ -z "${tgtfile}" ]] && \
  echo "error: missing output file" >&2 && \
  exit 1

specs=(
  "s3gw/longhorn-s3gw-secret.tmp"
  "s3gw/longhorn-storageclass"
  "s3gw/s3gw-namespace"
  "s3gw/s3gw-pvc"
  "s3gw/s3gw-config"
  "s3gw/s3gw-deployment.tmp"
  "s3gw/s3gw-secret"
  "s3gw/s3gw-service"
)

nginx_specs=(
  "ingress-nginx/nginx-nodeport"
  "ingress-nginx/longhorn-ingress"
  "ingress-nginx/longhorn-secret"
  "ingress-nginx/s3gw-ingress-no-tls"
  "ingress-nginx/s3gw-ingress-secret"
  "ingress-nginx/s3gw-ingress"
)

traefik_specs=(
  "ingress-traefik/longhorn-ingress"
  "ingress-traefik/s3gw-ingress"
)

d="$(date +'%Y/%M/%d %H:%m:%S %Z')"

cat > ${tgtfile} << EOF
# ${tgtfile} - setup a k3s cluster with longhorn and s3gw
# Copyright 2022 SUSE, LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This file was auto-generated by generate-spec.sh on ${d}
#

EOF

has_prior=false
for spec in ${specs[@]}; do
  echo Inflating s3gw-spec ${spec}.yaml
  ${has_prior} && echo "---" >> ${tgtfile}
  has_prior=true
  cat ${spec}.yaml >> ${tgtfile}
done

if [ $ingress = "nginx" ]; then
  for spec in ${nginx_specs[@]}; do
    echo Inflating nginx-spec ${spec}.yaml
    echo "---" >> ${tgtfile}
    cat ${spec}.yaml >> ${tgtfile}
  done
elif [ $ingress = "traefik" ]; then
  for spec in ${traefik_specs[@]}; do
    echo Inflating traefik-spec ${spec}.yaml
    echo "---" >> ${tgtfile}
    cat ${spec}.yaml >> ${tgtfile}
  done
fi

rm -f s3gw/*.tmp.yaml
