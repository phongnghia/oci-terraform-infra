/**
 * Networking Module - Outputs
 *
 * All values needed by the compute and storage modules, and by the
 * environment root module to wire cross-region DRG peering.
 */

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.main.id
}

output "vcn_cidr" {
  description = "Primary CIDR block of the VCN"
  value       = oci_core_vcn.main.cidr_blocks[0]
}

output "public_subnet_id" {
  description = "OCID of the public subnet"
  value       = oci_core_subnet.public.id
}

output "private_subnet_id" {
  description = "OCID of the private subnet"
  value       = oci_core_subnet.private.id
}

output "internet_gateway_id" {
  description = "OCID of the Internet Gateway"
  value       = oci_core_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "OCID of the NAT Gateway"
  value       = oci_core_nat_gateway.main.id
}

output "service_gateway_id" {
  description = "OCID of the Service Gateway"
  value       = oci_core_service_gateway.main.id
}

output "drg_id" {
  description = "OCID of the Dynamic Routing Gateway (DRG)"
  value       = oci_core_drg.main.id
}

output "drg_attachment_id" {
  description = "OCID of the DRG-to-VCN attachment"
  value       = oci_core_drg_attachment.main.id
}

output "dhcp_options_id" {
  description = "OCID of the custom DHCP Options"
  value       = oci_core_dhcp_options.main.id
}

output "security_list_id" {
  description = "OCID of the Windows Security List"
  value       = oci_core_security_list.windows.id
}

output "bastion_nsg_id" {
  description = "OCID of the NSG for the Windows bastion/jump-box"
  value       = oci_core_network_security_group.bastion.id
}

output "app_nsg_id" {
  description = "OCID of the NSG for Windows application servers"
  value       = oci_core_network_security_group.app.id
}
