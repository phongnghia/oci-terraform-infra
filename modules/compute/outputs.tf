/**
 * Compute Module - Outputs
 */

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.main.id
}

output "instance_display_name" {
  description = "Display name of the instance"
  value       = oci_core_instance.main.display_name
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = oci_core_instance.main.private_ip
}

output "public_ip" {
  description = "Public IP address of the instance, or null when no public IP is assigned"
  value       = oci_core_instance.main.public_ip
}

output "availability_domain" {
  description = "Availability Domain where the instance was created"
  value       = oci_core_instance.main.availability_domain
}

output "image_id" {
  description = "OCID of the image used to create the instance"
  value       = data.oci_core_images.os_image.images[0].id
}

output "image_display_name" {
  description = "Name of the image used to create the instance"
  value       = data.oci_core_images.os_image.images[0].display_name
}
