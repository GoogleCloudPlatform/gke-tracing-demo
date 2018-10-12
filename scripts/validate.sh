#! /usr/bin/env bash

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# "---------------------------------------------------------"
# "-                                                       -"
# "-  Validation script checks if demo application         -"
# "-  deployed successfully.                               -"
# "-                                                       -"
# "---------------------------------------------------------"

# Do not set exit on error, since the rollout status command may fail
set -o nounset
set -o pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

APP_NAME=$(kubectl get deployments -n default \
  -ojsonpath='{.items[0].metadata.labels.app}')
APP_MESSAGE="deployment \"$APP_NAME\" successfully rolled out"

cd "$ROOT/terraform" || exit; CLUSTER_NAME=$(terraform output cluster_name) \
  ZONE=$(terraform output primary_zone)

# Get credentials for the k8s cluster
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE"

SUCCESSFUL_ROLLOUT=false
for _ in {1..60}
do
  ROLLOUT=$(kubectl rollout status -n default \
    --watch=false deployment/"$APP_NAME") &> /dev/null
  if [[ $ROLLOUT = *"$APP_MESSAGE"* ]]; then
    SUCCESSFUL_ROLLOUT=true
    break
  fi
  sleep 2
  echo "Waiting for application deployment..."
done

if [ "$SUCCESSFUL_ROLLOUT" = false ]
then
  echo "ERROR - Timed out waiting for application deployment"
  exit 1
fi

echo "Step 1 of the validation passed. App is deployed."

# Loop for up to 60 seconds waiting for service's IP address
EXT_IP=""
for _ in {1..60}
do
  EXT_IP=$(kubectl get svc "$APP_NAME" -n default \
    -ojsonpath='{.status.loadBalancer.ingress[0].ip}')
  [ ! -z "$EXT_IP" ] && break
  sleep 2
  echo "Waiting for service availability..."
done
if [ -z "$EXT_IP" ]
then
  echo "ERROR - Timed out waiting for service"
  exit 1
fi

# Get service's port
EXT_PORT=$(kubectl get service "$APP_NAME" -n default \
  -o=jsonpath='{.spec.ports[0].port}')

echo "App is available at: http://$EXT_IP:$EXT_PORT"

STATUS_CODE=""
for _ in {1..60}
do
  # Test service availability
  STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$EXT_IP:$EXT_PORT/")
  [ ! -z "$STATUS_CODE" ] && break
  sleep 2
  echo "Waiting for service availability..."
done
if [ -z "$STATUS_CODE" ]
then
  echo "ERROR - Timed out waiting for service"
  exit 1
fi

if [ "$STATUS_CODE" != "200" ]
then
  echo "ERROR - Service is returning error"
  exit 1
fi

echo "Step 2 of the validation passed. App handles requests."
