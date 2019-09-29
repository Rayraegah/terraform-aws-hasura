# -----------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# -----------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# -----------------------------------------------------------------------------
# PARAMETERS
# -----------------------------------------------------------------------------

variable "region" {
  description = "Region to deploy"
  default     = "ap-northeast-1" # Asia Pacific Tokyo
}

variable "domain" {
  description = "Domain name. Service will be deployed at hasura.domain"
}

variable "app_subdomain" {
  description = "The Subdomain for your application that will make CORS requests to hasura.domain"
  default     = "app"
}
variable "hasura_version_tag" {
  description = "The hasura graphql engine version tag"
  default     = "v1.0.0-beta.3"
}

variable "hasura_admin_secret" {
  description = "The admin secret to secure hasura; for admin access"
}

variable "hasura_jwt_secret_key" {
  description = "The secret shared key for JWT verification"
}

variable "hasura_jwt_secret_algo" {
  description = "The algorithm for JWT verification (HS256 or RS256)"
  default     = "HS256"
}

variable "hasura_console_enabled" {
  description = "Should the Hasura Console web interface be enabled?"
  default     = "true"
}

variable "rds_username" {
  description = "The username for RDS"
}

variable "rds_password" {
  description = "The password for RDS"
}

variable "rds_db_name" {
  description = "The DB name in the RDS instance"
}

variable "rds_instance" {
  description = "The size of RDS instance, eg db.t2.micro"
}

variable "az_count" {
  description = "How many AZ's to create in the VPC"
  default     = 2
}

variable "multi_az" {
  description = "Whether to deploy RDS and ECS in multi AZ mode or not"
  default     = true
}

variable "vpc_enable_dns_hostnames" {
  description = "A boolean flag to enable/disable DNS hostnames in the VPC. Defaults false."
  default     = false
}

variable "environment" {
  description = "Environment variables for ECS task: [ { name = \"foo\", value = \"bar\" }, ..]"
  default     = []
}

variable "additional_db_security_groups" {
  description = "List of Security Group IDs to have access to the RDS instance"
  default = []
}