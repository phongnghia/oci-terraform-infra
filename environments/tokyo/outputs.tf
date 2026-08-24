/**
 * Tokyo Environment - Outputs
 *
 * Key resource identifiers printed after `terraform apply`.
 * The DRG ID is needed when configuring the Remote Peering Connection (RPC)
 * between Tokyo and Osaka.
 */

output "vcn_id" {
  description = "OCID of the Tokyo VCN"
  value       = module.networking.vcn_id
}

output "vcn_cidr" {
  description = "CIDR block of the Tokyo VCN"
  value       = module.networking.vcn_cidr
}

output "public_subnet_id" {
  description = "OCID of the Tokyo public subnet (bastion/jump-box)"
  value       = module.networking.public_subnet_id
}

output "private_subnet_id" {
  description = "OCID of the Tokyo private subnet (application servers)"
  value       = module.networking.private_subnet_id
}

output "nat_gateway_id" {
  description = "OCID of the Tokyo NAT Gateway"
  value       = module.networking.nat_gateway_id
}

output "service_gateway_id" {
  description = "OCID of the Tokyo Service Gateway"
  value       = module.networking.service_gateway_id
}

output "drg_id" {
  description = "OCID of the Tokyo DRG - required when creating the Remote Peering Connection to Osaka"
  value       = module.networking.drg_id
}

output "drg_attachment_id" {
  description = "OCID of the Tokyo DRG-to-VCN attachment"
  value       = module.networking.drg_attachment_id
}

output "dhcp_options_id" {
  description = "OCID of the Tokyo DHCP Options"
  value       = module.networking.dhcp_options_id
}

output "security_list_id" {
  description = "OCID of the Tokyo Windows Security List"
  value       = module.networking.security_list_id
}

output "bastion_nsg_id" {
  description = "OCID of the Tokyo bastion NSG"
  value       = module.networking.bastion_nsg_id
}

output "app_nsg_id" {
  description = "OCID of the Tokyo application server NSG"
  value       = module.networking.app_nsg_id
}
