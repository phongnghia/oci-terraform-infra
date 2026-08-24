/**
 * Tokyo Environment - Input Variables
 */

# OCI Authentication
# All values are sensitive and must be supplied via terraform.tfvars (never committed).

variable "tenancy_ocid" {
  description = "OCID of the OCI Tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user used for API authentication"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API signing key uploaded to the OCI user profile"
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the PEM private key file on the machine running Terraform (e.g. ~/.oci/oci_api_key.pem)"
  type        = string
}

# Project

variable "project_name" {
  description = "Project identifier used as a prefix in all resource names (lowercase letters and numbers only)"
  type        = string
  default     = "myproject"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "compartment_id" {
  description = "OCID of the Compartment where all resources will be created"
  type        = string
}

variable "owner_tag" {
  description = "Owner identifier for cost allocation and resource tagging (e.g. team email)"
  type        = string
  default     = "devops-team"
}

# Networking

variable "management_cidr" {
  description = "CIDR block of the trusted management network (on-premises office, VPN, or jump-box IP) allowed to RDP/WinRM into instances"
  type        = string

  validation {
    condition     = can(cidrhost(var.management_cidr, 0))
    error_message = "management_cidr must be a valid CIDR block (e.g. 203.0.113.0/28)."
  }
}

variable "dns_search_domain" {
  description = "DNS search domain configured via DHCP Option 119 (e.g. corp.example.com)"
  type        = string
  default     = "example.internal"
}
