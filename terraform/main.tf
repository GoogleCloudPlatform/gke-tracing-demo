/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Provides access to available Google Container Engine versions in a zone for a given project.
// https://www.terraform.io/docs/providers/google/d/google_container_engine_versions.html
data "google_container_engine_versions" "on-prem" {
  location = var.zone
  project = var.project
}

// https://www.terraform.io/docs/providers/google/d/google_container_cluster.html
// Create the primary cluster for this project.

// Create the GKE Cluster
resource "google_container_cluster" "primary" {
  name               = "tracing-demo-space"
  location           = var.zone
  initial_node_count = 1
  min_master_version = data.google_container_engine_versions.on-prem.latest_master_version

  // Scopes were a pre-IAM method of giving instances API access
  // They are still around we need to give our cluster nodes
  // access to PubSub and Tracing as well as the standard scopes
  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  // Here we use gcloud to gather authentication information about our new cluster and write that
  // information to kubectls config file
  // Here we use gcloud to gather authentication information about our new cluster and write that
  // information to kubectls config file
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${google_container_cluster.primary.location} --project ${var.project}"
  }
}

// Creates a Cloud Pub/Sub Topic
resource "google_pubsub_topic" "tracing-demo-topic" {
  name = "tracing-demo"
}

// Creates a Cloud Pub/Sub Subscription
// You need a subscription to pull messages from a topic
resource "google_pubsub_subscription" "tracing-demo-subscription" {
  name  = "tracing-demo-cli"
  topic = google_pubsub_topic.tracing-demo-topic.name
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "primary_zone" {
  value = google_container_cluster.primary.location
}
