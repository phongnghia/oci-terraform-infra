/**
 * Networking Module - OCI Full Network Stack
 *
 * Provisions all network resources for a single region/VCN, including:
 *   - VCN
 *   - DHCP Options (custom DNS configuration)
 *   - Subnets (public and private)
 *   - Internet Gateway  (public subnet to internet, bidirectional)
 *   - NAT Gateway       (private subnet to internet, outbound only)
 *   - Service Gateway   (private subnet to OCI services, no internet)
 *   - Dynamic Routing Gateway (DRG) + VCN attachment
 *   - Route Tables (public, private)
 *   - Security List     (subnet-level stateful firewall)
 *   - Network Security Groups (NSG) + Rules for Windows workloads
 *
 * Windows-specific ports covered:
 *   - RDP  3389/TCP  - remote desktop from bastion NSG
 *   - WinRM 5985/TCP - Windows Remote Management (HTTP)
 *   - WinRM 5986/TCP - Windows Remote Management (HTTPS)
 *   - SMB   445/TCP  - file sharing within VCN
 *   - ICMP           - ping within VCN for diagnostics
 */

# Data sources for OCI managed services.

# Retrieve all OCI managed services available for the Service Gateway in this region.
# The filter selects the "All <region> Services" bundle so a single rule covers
# Object Storage, Streaming, and other OCI services without listing each CIDR.
data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-vcn"

  # dns_label must be alphanumeric and no longer than 15 characters.
  dns_label = "${var.project_name}${var.environment}${var.region_key}"

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-vcn"
  })
}

# Custom DHCP options assigned to every subnet in this VCN.
# Using VcnLocalPlusInternet resolver so instances can resolve both internal
# hostnames (*.oraclevcn.com) and public DNS names.
resource "oci_core_dhcp_options" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-dhcp"

  # Option 1: DNS resolver type
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }

  # Option 2: search domain appended to unqualified hostnames
  options {
    type                = "SearchDomain"
    search_domain_names = [var.dns_search_domain]
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-dhcp"
  })
}

# NAT Gateway - outbound-only internet access for private subnet instances.
# Windows VMs in the private subnet use this to reach Windows Update, etc.
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-nat"
  block_traffic  = false

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-nat"
  })
}

# Service Gateway - reaches OCI managed services (Object Storage, Streaming, etc.)
# over the OCI internal backbone without traversing the public internet.
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-sgw"

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-sgw"
  })
}

# Dynamic Routing Gateway - the hub for cross-region, on-premises, or
# FastConnect/VPN connectivity. Attaching it to the VCN enables DRG-based
# routing rules in route tables.
resource "oci_core_drg" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-drg"

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-drg"
  })
}

# DRG Attachment - binds the DRG to this VCN.
# After attachment, route table rules can forward traffic to the DRG for
# cross-region or on-premises routing.
resource "oci_core_drg_attachment" "main" {
  drg_id       = oci_core_drg.main.id
  display_name = "${var.project_name}-${var.environment}-${var.region_key}-drg-attachment"

  network_details {
    id   = oci_core_vcn.main.id
    type = "VCN"
  }
}

# Subnet-level stateful firewall rules applied to all VNICs in the subnet.
# For Windows workloads the critical ingress ports are:
#   3389 - RDP (remote desktop)
#   5985 - WinRM HTTP
#   5986 - WinRM HTTPS
#   445  - SMB (file sharing)
# ICMP type 3 (Destination Unreachable) is required for path MTU discovery.
resource "oci_core_security_list" "windows" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-windows-sl"

  # Egress rules.

  # Allow all outbound TCP/UDP so Windows VMs can reach Windows Update,
  # OCI services, and cross-region peers without restriction at this layer.
  # Fine-grained egress control is enforced at the NSG level.
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound traffic"
    stateless   = false
  }

  # Ingress rules.

  # RDP - allow from the trusted management CIDR (e.g. on-premises or bastion subnet)
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.management_cidr
    description = "Allow RDP from management network"
    stateless   = false

    tcp_options {
      min = 3389
      max = 3389
    }
  }

  # WinRM HTTP - used by Ansible/automation tools for Windows configuration
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.management_cidr
    description = "Allow WinRM HTTP from management network"
    stateless   = false

    tcp_options {
      min = 5985
      max = 5985
    }
  }

  # WinRM HTTPS - encrypted WinRM channel
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.management_cidr
    description = "Allow WinRM HTTPS from management network"
    stateless   = false

    tcp_options {
      min = 5986
      max = 5986
    }
  }

  # SMB - Windows file sharing within the VCN only
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.vcn_cidr
    description = "Allow SMB file sharing within VCN"
    stateless   = false

    tcp_options {
      min = 445
      max = 445
    }
  }

  # ICMP type 3 (Destination Unreachable) - required for path MTU discovery
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = var.vcn_cidr
    description = "Allow ICMP type 3 (Destination Unreachable) within VCN"
    stateless   = false

    icmp_options {
      type = 3
    }
  }

  # ICMP type 8 (Echo Request / ping) - diagnostics within VCN
  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = var.vcn_cidr
    description = "Allow ICMP ping within VCN"
    stateless   = false

    icmp_options {
      type = 8
    }
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-windows-sl"
  })
}

# Public subnet route table.
# Default route to the Internet Gateway so bastion/jump-box instances have
# bidirectional internet connectivity.
# DRG route for cross-region or on-premises traffic via the DRG.
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
    description       = "Default route to internet via Internet Gateway"
  }

  dynamic "route_rules" {
    for_each = var.cross_region_cidrs
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_drg.main.id
      description       = "Cross-region / on-premises route via DRG"
    }
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-public-rt"
  })
}

# Route Table for Private Subnet.
# Default route to the NAT Gateway for outbound internet access.
# OCI services route to the Service Gateway without an internet hop.
# Cross-region route to the DRG for Tokyo, Osaka, or on-premises traffic.
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
    description       = "Default outbound route via NAT Gateway (no inbound)"
  }

  route_rules {
    destination       = data.oci_core_services.all_oci_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
    description       = "OCI managed services via Service Gateway (no internet)"
  }

  dynamic "route_rules" {
    for_each = var.cross_region_cidrs
    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_drg.main.id
      description       = "Cross-region / on-premises route via DRG"
    }
  }

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-private-rt"
  })
}

# Internet Gateway - attached to the public subnet route table.
# Required for the bastion/jump-box to be reachable from the internet via RDP.
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-igw"
  enabled        = true

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-igw"
  })
}

# Public subnet - hosts the Windows bastion/jump-box.
# Instances here receive a public IP and are reachable via RDP from the internet
# (restricted to management_cidr by the Security List and NSG).
resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.public_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-${var.region_key}-public-subnet"
  dns_label         = "pub${var.region_key}"
  dhcp_options_id   = oci_core_dhcp_options.main.id
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.windows.id]

  # Public subnet: allow public IPs on VNICs
  prohibit_public_ip_on_vnic = false

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-public-subnet"
    Tier = "public"
  })
}

# Private subnet - hosts Windows application servers.
# No public IP; internet access is outbound-only via NAT Gateway.
# RDP access is only possible through the bastion in the public subnet.
resource "oci_core_subnet" "private" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.private_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-${var.region_key}-private-subnet"
  dns_label         = "prv${var.region_key}"
  dhcp_options_id   = oci_core_dhcp_options.main.id
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.windows.id]

  # Private subnet: block public IPs on all VNICs
  prohibit_public_ip_on_vnic = true

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-private-subnet"
    Tier = "private"
  })
}

# NSG: Bastion (Windows Jump-Box) - placed in the public subnet.
# Allows RDP inbound from the trusted management CIDR only.
resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-bastion-nsg"

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-bastion-nsg"
    Role = "bastion"
  })
}

# Bastion NSG - Ingress: RDP from management CIDR
resource "oci_core_network_security_group_security_rule" "bastion_ingress_rdp" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow RDP (3389) from trusted management CIDR"
  source                    = var.management_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

# Bastion NSG - Ingress: ICMP ping from management CIDR for connectivity checks
resource "oci_core_network_security_group_security_rule" "bastion_ingress_icmp" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  description               = "Allow ICMP ping from management CIDR"
  source                    = var.management_cidr
  source_type               = "CIDR_BLOCK"

  icmp_options {
    type = 8 # Echo Request
  }
}

# Bastion NSG - Egress: all outbound traffic allowed
resource "oci_core_network_security_group_security_rule" "bastion_egress_all" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "EGRESS"
  protocol                  = "all"
  description               = "Allow all outbound traffic from bastion"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# NSG: Windows Application Servers - placed in the private subnet.
# RDP is only accepted from the bastion NSG (not from the internet).
# WinRM is accepted from the management CIDR for automation/Ansible.
resource "oci_core_network_security_group" "app" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-${var.region_key}-app-nsg"

  freeform_tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-${var.region_key}-app-nsg"
    Role = "application"
  })
}

# App NSG - Ingress: RDP from bastion NSG only.
# Referencing the bastion NSG ID (not a CIDR) means this rule remains correct
# even if the bastion instance is replaced and gets a new IP address.
resource "oci_core_network_security_group_security_rule" "app_ingress_rdp_from_bastion" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow RDP (3389) from bastion NSG only"
  source                    = oci_core_network_security_group.bastion.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}

# App NSG - Ingress: WinRM HTTP from management CIDR (automation/Ansible)
resource "oci_core_network_security_group_security_rule" "app_ingress_winrm_http" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow WinRM HTTP (5985) from management CIDR"
  source                    = var.management_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 5985
      max = 5985
    }
  }
}

# App NSG - Ingress: WinRM HTTPS from management CIDR
resource "oci_core_network_security_group_security_rule" "app_ingress_winrm_https" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow WinRM HTTPS (5986) from management CIDR"
  source                    = var.management_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 5986
      max = 5986
    }
  }
}

# App NSG - Ingress: SMB file sharing within VCN
resource "oci_core_network_security_group_security_rule" "app_ingress_smb" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  description               = "Allow SMB (445) within VCN for file sharing"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 445
      max = 445
    }
  }
}

# App NSG - Ingress: ICMP ping within VCN for diagnostics
resource "oci_core_network_security_group_security_rule" "app_ingress_icmp" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "1" # ICMP
  description               = "Allow ICMP ping within VCN"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"

  icmp_options {
    type = 8 # Echo Request
  }
}

# App NSG - Egress: all outbound traffic allowed
resource "oci_core_network_security_group_security_rule" "app_egress_all" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "EGRESS"
  protocol                  = "all"
  description               = "Allow all outbound traffic from app servers"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}
