terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 7.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 7.0" }
  }
}
provider "google" {
  project = var.project_id
  region  = var.region
}
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
data "google_project" "nextbell" { project_id = var.project_id }
locals {
  runtime_roles = toset([
    "roles/datastore.user", "roles/firebaseauth.admin", "roles/firebasecloudmessaging.admin",
    "roles/cloudtasks.enqueuer"
  ])
  oidc_subject = "owner:${var.vercel_team_slug}:project:${var.vercel_project_name}:environment:${var.vercel_environment}"
}
resource "google_project_service" "api" {
  for_each = toset([
    "calendar-json.googleapis.com", "tasks.googleapis.com", "firebase.googleapis.com",
    "identitytoolkit.googleapis.com", "securetoken.googleapis.com", "firestore.googleapis.com",
    "fcm.googleapis.com", "fcmregistrations.googleapis.com", "firebaseinstallations.googleapis.com",
    "cloudtasks.googleapis.com", "cloudscheduler.googleapis.com", "cloudkms.googleapis.com",
    "secretmanager.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com",
    "sts.googleapis.com", "billingbudgets.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}
resource "google_firebase_project" "nextbell" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.api]
}
resource "google_firebase_android_app" "nextbell" {
  provider     = google-beta
  project      = var.project_id
  display_name = "Nextbell Android beta"
  package_name = "com.suhel.nextbell"
  depends_on   = [google_firebase_project.nextbell]
}
resource "google_firestore_database" "nextbell" {
  project                           = var.project_id
  name                              = "(default)"
  location_id                       = var.region
  type                              = "FIRESTORE_NATIVE"
  delete_protection_state           = "DELETE_PROTECTION_ENABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  depends_on                        = [google_project_service.api]
}
resource "google_firestore_backup_schedule" "daily" {
  project   = var.project_id
  database  = google_firestore_database.nextbell.name
  retention = "604800s"
  daily_recurrence {}
}
resource "google_service_account" "runtime" {
  account_id   = "nextbell-runtime"
  display_name = "Nextbell beta API and sync worker"
  depends_on   = [google_project_service.api]
}
resource "google_service_account" "jobs" {
  account_id   = "nextbell-jobs"
  display_name = "Nextbell job request identity"
  depends_on   = [google_project_service.api]
}
resource "google_project_iam_member" "runtime" {
  for_each = local.runtime_roles
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_service_account_iam_member" "enqueue_as_jobs" {
  service_account_id = google_service_account.jobs.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_kms_key_ring" "tokens" {
  name       = "nextbell"
  location   = var.region
  depends_on = [google_project_service.api]
}
resource "google_kms_crypto_key" "tokens" {
  name            = "google-refresh-tokens"
  key_ring        = google_kms_key_ring.tokens.id
  rotation_period = "7776000s"
  lifecycle { prevent_destroy = true }
}
resource "google_kms_crypto_key_iam_member" "runtime" {
  crypto_key_id = google_kms_crypto_key.tokens.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_secret_manager_secret" "oauth" {
  secret_id = "nextbell-google-oauth"
  replication {
    user_managed {
      replicas { location = var.region }
    }
  }
  depends_on = [google_project_service.api]
}
resource "google_secret_manager_secret_iam_member" "runtime" {
  secret_id = google_secret_manager_secret.oauth.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
resource "google_iam_workload_identity_pool" "vercel" {
  workload_identity_pool_id = "nextbell-vercel"
  display_name              = "Nextbell beta Vercel"
  depends_on                = [google_project_service.api]
}
resource "google_iam_workload_identity_pool_provider" "vercel" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.vercel.workload_identity_pool_id
  workload_identity_pool_provider_id = "beta"
  attribute_mapping                  = { "google.subject" = "assertion.sub" }
  attribute_condition                = "assertion.sub == '${local.oidc_subject}'"
  oidc {
    issuer_uri        = "https://oidc.vercel.com/${var.vercel_team_slug}"
    allowed_audiences = ["https://vercel.com/${var.vercel_team_slug}"]
  }
}
resource "google_service_account_iam_member" "federation" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.vercel.name}/subject/${local.oidc_subject}"
}
resource "google_cloud_tasks_queue" "sync" {
  name          = "nextbell-sync"
  location      = var.region
  desired_state = var.jobs_paused ? "PAUSED" : "RUNNING"
  rate_limits {
    max_dispatches_per_second = 1
    max_concurrent_dispatches = 2
  }
  retry_config {
    max_attempts       = 20
    max_retry_duration = "3600s"
    min_backoff        = "15s"
    max_backoff        = "600s"
    max_doublings      = 5
  }
  depends_on = [google_project_service.api]
}
resource "google_cloud_scheduler_job" "jobs" {
  for_each         = { dispatch = "*/5 * * * *", maintenance = "17 * * * *" }
  name             = "nextbell-${each.key}"
  region           = var.region
  schedule         = each.value
  time_zone        = "Etc/UTC"
  paused           = var.jobs_paused
  attempt_deadline = "240s"
  http_target {
    http_method = "POST"
    uri         = "${var.api_origin}/api/internal/jobs"
    headers     = { "Content-Type" = "application/json" }
    body        = base64encode(jsonencode({ type = each.key }))
    oidc_token {
      service_account_email = google_service_account.jobs.email
      audience              = "${var.api_origin}/api/internal/jobs"
    }
  }
  depends_on = [google_project_service.api]
}
resource "google_billing_budget" "beta" {
  billing_account = var.billing_account_id
  display_name    = "Nextbell private beta — $25 target"
  budget_filter {
    projects = ["projects/${data.google_project.nextbell.number}"]
  }
  amount {
    specified_amount {
      currency_code = "USD"
      units         = "25"
    }
  }
  threshold_rules { threshold_percent = 0.4 }
  threshold_rules { threshold_percent = 0.8 }
  threshold_rules { threshold_percent = 1.0 }
  depends_on = [google_project_service.api]
}
