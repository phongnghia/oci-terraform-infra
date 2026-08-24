/**
 * Storage Module - Outputs
 */

output "block_volume_id" {
  description = "OCID of the block volume"
  value       = oci_core_volume.data.id
}

output "block_volume_display_name" {
  description = "Display name of the block volume"
  value       = oci_core_volume.data.display_name
}

output "volume_attachment_id" {
  description = "OCID of the volume attachment"
  value       = oci_core_volume_attachment.data.id
}

output "volume_attachment_device" {
  description = "Device path of the volume on the instance, such as /dev/oracleoci/oraclevdb"
  value       = oci_core_volume_attachment.data.device
}

output "bucket_name" {
  description = "Name of the Object Storage bucket"
  value       = oci_objectstorage_bucket.main.name
}

output "bucket_namespace" {
  description = "Object Storage namespace"
  value       = data.oci_objectstorage_namespace.tenancy.namespace
}

output "bucket_access_uri" {
  description = "URI for accessing the bucket through the OCI CLI or SDK"
  value       = "oci:///${oci_objectstorage_bucket.main.name}@${data.oci_objectstorage_namespace.tenancy.namespace}"
}
