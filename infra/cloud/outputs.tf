output "runtime_environment" {
  value = {
    GOOGLE_CLOUD_PROJECT           = var.project_id
    GOOGLE_CLOUD_REGION            = var.region
    GOOGLE_RUNTIME_SERVICE_ACCOUNT = google_service_account.runtime.email
    GOOGLE_JOB_SERVICE_ACCOUNT     = google_service_account.jobs.email
    GOOGLE_WORKLOAD_AUDIENCE       = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.vercel.name}"
    GOOGLE_TOKEN_KEY               = google_kms_crypto_key.tokens.id
    GOOGLE_OAUTH_SECRET_VERSION    = "${google_secret_manager_secret.oauth.id}/versions/latest"
    NEXTBELL_API_ORIGIN            = var.api_origin
    NEXTBELL_SYNC_PAUSED           = tostring(var.jobs_paused)
  }
}
output "firebase_android_app_id" { value = google_firebase_android_app.nextbell.app_id }
output "project_number" { value = data.google_project.nextbell.number }
