/**
 * Storage Module - OCI Block Volume and Object Storage
 *
 * Creates:
 * - Block Volume attached to a compute instance
 * - Block Volume Attachment
 * - Object Storage Bucket for logs, backups, and static files
 */

# Block Volume for instance data
resource "oci_core_volume" "data" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = "${var.project_name}-${var.environment}-${var.volume_name}-vol"
  size_in_gbs         = var.volume_size_gb

  # VPUs (Volume Performance Units): 0=Low, 10=Balanced, 20=High, 30=Ultra High
  vpus_per_gb = var.volume_vpus_per_gb

  # Apply the selected backup policy only when one is configured.
  dynamic "source_details" {
    for_each = var.volume_backup_policy_id != "" ? [1] : []
    content {
      type = "volumeBackupPolicy"
      id   = var.volume_backup_policy_id
    }
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.volume_name}-vol"
    Role = var.volume_name
  })
}

# Attach the data volume to the compute instance.
resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized" # Preferred over iSCSI for most workloads.
  instance_id     = var.instance_id
  volume_id       = oci_core_volume.data.id
  display_name    = "${var.project_name}-${var.environment}-${var.volume_name}-attachment"

  # Read-only mode is useful when the volume is shared by multiple instances.
  is_read_only = var.is_read_only

  # Enable this only when shared storage is required.
  is_shareable = var.is_shareable
}

# Retrieve the Object Storage namespace for the tenancy.
data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.compartment_id
}

# Object Storage bucket for files, logs, and backups.
resource "oci_objectstorage_bucket" "main" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.tenancy.namespace
  name           = "${var.project_name}-${var.environment}-${var.bucket_name}"

  # ObjectRead permits unauthenticated reads and should only be used for static assets.
  # NoPublicAccess restricts access to authenticated users and is the recommended default.
  access_type = var.bucket_access_type

  # Retain previous object versions when versioning is enabled.
  versioning = var.enable_versioning ? "Enabled" : "Disabled"

  # Object Storage encrypts data with an Oracle-managed key by default.

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.bucket_name}"
  })
}

# Apply lifecycle rules to archive and delete objects after configured periods.
resource "oci_objectstorage_object_lifecycle_policy" "main" {
  count = var.enable_lifecycle_policy ? 1 : 0

  namespace = data.oci_objectstorage_namespace.tenancy.namespace
  bucket    = oci_objectstorage_bucket.main.name

  rules {
    name        = "archive-old-objects"
    action      = "ARCHIVE"
    is_enabled  = true
    time_amount = var.archive_after_days
    time_unit   = "DAYS"

    object_name_filter {
      inclusion_prefixes = ["logs/", "backups/"]
    }
  }

  rules {
    name        = "delete-expired-objects"
    action      = "DELETE"
    is_enabled  = true
    time_amount = var.delete_after_days
    time_unit   = "DAYS"

    object_name_filter {
      inclusion_prefixes = ["temp/", "cache/"]
    }
  }
}
