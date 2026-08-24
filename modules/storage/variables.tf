/**
 * Storage Module - Input Variables
 */

variable "compartment_id" {
  description = "OCID of the OCI Compartment"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev, staging, or prod"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain for the block volume; must match the instance Availability Domain"
  type        = string
}

variable "instance_id" {
  description = "OCID of the compute instance to which the block volume is attached"
  type        = string
}

variable "volume_name" {
  description = "Volume identifier, such as data, logs, or backup"
  type        = string
  default     = "data"
}

variable "volume_size_gb" {
  description = "Block volume size in GB; minimum 50 GB"
  type        = number
  default     = 100

  validation {
    condition     = var.volume_size_gb >= 50 && var.volume_size_gb <= 32768
    error_message = "volume_size_gb must be between 50 and 32768 GB."
  }
}

variable "volume_vpus_per_gb" {
  description = "Volume Performance Units: 0 = Low Cost, 10 = Balanced, 20 = High Performance, 30 = Ultra High Performance"
  type        = number
  default     = 10

  validation {
    condition     = contains([0, 10, 20, 30], var.volume_vpus_per_gb)
    error_message = "volume_vpus_per_gb must be 0, 10, 20, or 30."
  }
}

variable "volume_backup_policy_id" {
  description = "OCID of the backup policy; leave empty to disable backups"
  type        = string
  default     = ""
}

variable "is_read_only" {
  description = "Attach the volume in read-only mode"
  type        = bool
  default     = false
}

variable "is_shareable" {
  description = "Allow multiple instances to attach the volume"
  type        = bool
  default     = false
}

variable "bucket_name" {
  description = "Suffix for the Object Storage bucket name"
  type        = string
  default     = "storage"
}

variable "bucket_access_type" {
  description = "Bucket access type: NoPublicAccess, ObjectRead, or ObjectReadWithoutList"
  type        = string
  default     = "NoPublicAccess"

  validation {
    condition     = contains(["NoPublicAccess", "ObjectRead", "ObjectReadWithoutList"], var.bucket_access_type)
    error_message = "bucket_access_type must be NoPublicAccess, ObjectRead, or ObjectReadWithoutList."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the Object Storage bucket"
  type        = bool
  default     = false
}

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle rules to archive or delete old objects"
  type        = bool
  default     = false
}

variable "archive_after_days" {
  description = "Number of days before objects move to the Archive tier"
  type        = number
  default     = 30
}

variable "delete_after_days" {
  description = "Number of days before objects in the temp or cache prefixes are deleted"
  type        = number
  default     = 7
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
