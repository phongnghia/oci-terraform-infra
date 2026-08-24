/**
 * Networking Module - Input Variables
 */

variable "compartment_id" {
  description = "OCID of the OCI Compartment where all networking resources will be created"
  type        = string
}

variable "project_name" {
  description = "Project name used as a prefix for all resource display names (lowercase letters and numbers only)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region_key" {
  description = "Short region identifier appended to resource names to distinguish multi-region deployments (e.g. tky for Tokyo, osk for Osaka)"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.region_key))
    error_message = "region_key must be 2-6 lowercase letters (e.g. tky, osk)."
  }
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN. Must not overlap with the peer region VCN CIDR when DRG peering is used."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (must be within vcn_cidr)"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (must be within vcn_cidr)"
  type        = string
}

variable "management_cidr" {
  description = "CIDR block of the trusted management network allowed to RDP/WinRM into instances (e.g. on-premises office IP range or VPN CIDR)"
  type        = string

  validation {
    condition     = can(cidrhost(var.management_cidr, 0))
    error_message = "management_cidr must be a valid CIDR block."
  }
}

variable "cross_region_cidrs" {
  description = "List of CIDR blocks in the peer region (or on-premises) that should be routed via the DRG. Example: [\"10.1.0.0/16\"] for the Osaka VCN when deploying Tokyo."
  type        = list(string)
  default     = []
}

variable "dns_search_domain" {
  description = "DNS search domain appended to unqualified hostnames by DHCP Option 119 (e.g. example.internal)"
  type        = string
  default     = "example.internal"
}

variable "common_tags" {
  description = "Map of freeform tags applied to every resource created by this module"
  type        = map(string)
  default     = {}
}
