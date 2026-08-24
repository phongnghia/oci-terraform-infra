/**
 * Osaka Region - Network Infrastructure
 *
 * OCI Region: ap-osaka-1
 * Region key: osk
 *
 * Deploys the full network stack for the Osaka region:
 *   - VCN  10.1.0.0/16  (non-overlapping with Tokyo 10.0.0.0/16)
 *   - Public subnet  10.1.1.0/24  (Windows bastion/jump-box)
 *   - Private subnet 10.1.2.0/24  (Windows application servers)
 *   - Internet Gateway, NAT Gateway, Service Gateway
 *   - DRG + VCN attachment (for Osaka to Tokyo peering)
 *   - DHCP Options
 *   - Security List (Windows ports: RDP 3389, WinRM 5985/5986, SMB 445, ICMP)
 *   - NSG: bastion-nsg, app-nsg (with all rules)
 *
 * Cross-region peering:
 *   After both regions are deployed, create a Remote Peering Connection (RPC)
 *   between the Osaka DRG and the Tokyo DRG. The Tokyo VCN CIDR (10.0.0.0/16)
 *   is added to cross_region_cidrs so route tables forward inter-region traffic
 *   through the DRG automatically.
 *
 * Deadline: 2025-05-16
 */

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.12.0"
    }
  }

  # Remote State Backend (OCI Object Storage)
  # Uncomment and fill in after creating the state bucket.
  # Use a separate state key from Tokyo to avoid state conflicts.
  # backend "http" {
  #   address       = "https://objectstorage.ap-osaka-1.oraclecloud.com/p/<PAR_TOKEN>/n/<NAMESPACE>/b/tfstate-<project>/o/osaka/terraform.tfstate"
  #   update_method = "PUT"
  # }
}

# Provider for the Osaka region.
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = "ap-osaka-1"
}

# Common tags applied to every resource in this environment.
locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    region      = "ap-osaka-1"
    managed-by  = "terraform"
    owner       = var.owner_tag
  }
}

# Networking module for the full Osaka network stack.
module "networking" {
  source = "../../modules/networking"

  compartment_id      = var.compartment_id
  project_name        = var.project_name
  environment         = var.environment
  region_key          = "osk"
  vcn_cidr            = "10.1.0.0/16"
  public_subnet_cidr  = "10.1.1.0/24"
  private_subnet_cidr = "10.1.2.0/24"
  management_cidr     = var.management_cidr
  dns_search_domain   = var.dns_search_domain

  # Route traffic destined for the Tokyo VCN (10.0.0.0/16) through the DRG.
  # After deploying both regions, configure a Remote Peering Connection (RPC)
  # between the Osaka DRG and the Tokyo DRG.
  cross_region_cidrs = ["10.0.0.0/16"]

  common_tags = local.common_tags
}
