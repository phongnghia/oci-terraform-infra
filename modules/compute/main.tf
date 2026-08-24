/**
 * Compute Module - OCI Virtual Machine Instance
 *
 * Creates a Compute Instance (VM) with:
 * - Boot volume from a platform image
 * - Attached to the specified subnet and NSGs
 * - SSH key authentication (no password login)
 * - Optional cloud-init script for first-boot configuration
 */

# Data source: retrieve the first Availability Domain in the region
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

# Data source: retrieve the latest platform image matching the specified OS and shape
data "oci_core_images" "os_image" {
  compartment_id           = var.compartment_id
  operating_system         = var.os_name
  operating_system_version = var.os_version
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  # Only platform images (not custom images)
  filter {
    name   = "launch_mode"
    values = ["NATIVE", "PARAVIRTUALIZED"]
  }
}

# Compute Instance
resource "oci_core_instance" "main" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = "${var.project_name}-${var.environment}-${var.instance_role}"
  shape               = var.instance_shape

  # OCPU and memory configuration is required only for Flex shapes.
  dynamic "shape_config" {
    for_each = can(regex("Flex", var.instance_shape)) ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_in_gbs
    }
  }

  # Use the latest matching platform image.
  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.os_image.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  # VNIC (network interface) configuration
  create_vnic_details {
    subnet_id              = var.subnet_id
    display_name           = "${var.project_name}-${var.environment}-${var.instance_role}-vnic"
    assign_public_ip       = var.assign_public_ip
    hostname_label         = "${var.project_name}-${var.environment}-${var.instance_role}"
    nsg_ids                = var.nsg_ids
    skip_source_dest_check = false
  }

  # SSH public key for login; password authentication is disabled.
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = var.cloud_init_script != "" ? base64encode(var.cloud_init_script) : null
  }

  preserve_boot_volume = var.preserve_boot_volume

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.instance_role}"
    Role = var.instance_role
  })

  lifecycle {
    # Ignore image ID changes to prevent unintended instance replacement when
    # OCI publishes a new platform image version.
    ignore_changes = [source_details[0].source_id]
  }
}
