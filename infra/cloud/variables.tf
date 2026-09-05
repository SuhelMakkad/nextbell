variable "project_id" {
  type    = string
  default = "nextbell-507711"
}
variable "region" {
  type    = string
  default = "asia-south1"
}
variable "billing_account_id" {
  type        = string
  description = "The separate Nextbell billing account, already linked to the project. Never use OSS CRM."
}
variable "api_origin" {
  type        = string
  description = "Stable HTTPS origin of the dedicated private beta Vercel project. No trailing slash."
  validation {
    condition     = can(regex("^https://[^/]+$", var.api_origin))
    error_message = "Use an HTTPS origin without a path."
  }
}
variable "vercel_team_slug" { type = string }
variable "vercel_project_name" {
  type        = string
  description = "Exact project name from the verified Vercel OIDC subject. Use a separate beta project."
}
variable "vercel_environment" {
  type    = string
  default = "production"
}
variable "jobs_paused" {
  type        = bool
  default     = true
  description = "Keep workers paused until OAuth, deployment and authentication probes pass."
}
