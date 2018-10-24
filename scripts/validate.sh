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

# Define retry constants
readonly MAX_COUNT=60
readonly RETRY_COUNT=0
readonly SLEEP=2

readonly ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"

readonly APP_NAME=$(kubectl get deployments -n default \
  -ojsonpath='{.items[0].metadata.labels.app}')
readonly APP_MESSAGE="deployment \"$APP_NAME\" successfully rolled out"

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
for _ in {1..60}
do
  # Get service's ip
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

# Curl for the service with retries
STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$EXT_IP:$EXT_PORT/")
until [[ $STATUS_CODE -eq 200 ]]; do
    if [[ "${RETRY_COUNT}" -gt "${MAX_COUNT}" ]]; then
     # failed with retry, lets check whatz wrong and bail
     echo "Retry count exceeded. Exiting..."
     # Timed out?
     if [ -z "$STATUS_CODE" ]
     then
       echo "ERROR - Timed out waiting for service"
       exit 1
     fi
     # HTTP status not okay?
     if [ "$STATUS_CODE" != "200" ]
     then
       echo "ERROR - Service is returning error"
       exit 1
     fi
    fi
    NUM_SECONDS="$(( RETRY_COUNT * SLEEP ))"
    echo "Waiting for service availability..."
    echo "service / did not return an HTTP 200 response code after ${NUM_SECONDS} seconds"
    sleep "${SLEEP}"
    RETRY_COUNT="$(( RETRY_COUNT + 1 ))"
    STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$EXT_IP:$EXT_PORT/")
done

# succeeded, let's report it
echo "service / returns an HTTP 200 response code"
echo "Step 2 of the validation passed. App handles requests."
