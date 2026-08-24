/**
 * Compute Module - Input Variables
 */

variable "compartment_id" {
  description = "OCID of the OCI Compartment where the instance is created"
  type        = string
}

variable "project_name" {
  description = "Project name used to name resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
}

variable "instance_role" {
  description = "Instance role, such as bastion, app, or db"
  type        = string
  default     = "app"
}

variable "availability_domain_index" {
  description = "Availability Domain index: 0, 1, or 2"
  type        = number
  default     = 0

  validation {
    condition     = var.availability_domain_index >= 0 && var.availability_domain_index <= 2
    error_message = "availability_domain_index must be between 0 and 2."
  }
}

variable "instance_shape" {
  description = "OCI instance shape, such as VM.Standard.E4.Flex or VM.Standard3.Flex"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  description = "Number of OCPUs for a Flex shape (1 OCPU = 2 vCPUs)"
  type        = number
  default     = 1

  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 64
    error_message = "ocpus must be between 1 and 64."
  }
}

variable "memory_in_gbs" {
  description = "Memory in GB for a Flex shape"
  type        = number
  default     = 8

  validation {
    condition     = var.memory_in_gbs >= 1 && var.memory_in_gbs <= 1024
    error_message = "memory_in_gbs must be between 1 and 1024."
  }
}

variable "os_name" {
  description = "Operating system name, such as Oracle Linux or Canonical Ubuntu"
  type        = string
  default     = "Oracle Linux"
}

variable "os_version" {
  description = "Operating system version, such as 8, 9, or 22.04"
  type        = string
  default     = "8"
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB; minimum 50 GB"
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_gb >= 50 && var.boot_volume_size_gb <= 32768
    error_message = "boot_volume_size_gb must be between 50 and 32768 GB."
  }
}

variable "subnet_id" {
  description = "OCID of the subnet where the instance is created"
  type        = string
}

variable "nsg_ids" {
  description = "List of Network Security Group OCIDs attached to the instance"
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP; use true for bastion instances and false for application servers"
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "SSH public key content used to log in to the instance"
  type        = string
  sensitive   = true
}

variable "cloud_init_script" {
  description = "Cloud-init Bash script to run when the instance starts for the first time"
  type        = string
  default     = ""
}

variable "preserve_boot_volume" {
  description = "Whether to preserve the boot volume when the instance is deleted; recommended for production"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
