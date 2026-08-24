# Guide 2: OCI Concepts for Network Engineers

## OCI Global Architecture

Understanding how OCI organizes its infrastructure is essential before writing
any Terraform code. Every resource you create lives within this hierarchy:

```
Tenancy  (your OCI account — the root of everything)
└── Region  (physical data center location, e.g. ap-tokyo-1)
    └── Availability Domain (AD)  (isolated data center within a region)
        └── Fault Domain (FD)     (separate power/network rack within an AD)
            └── Compartment       (logical grouping for access control and billing)
                ├── VCN           (your private virtual network)
                │   ├── Subnet
                │   ├── Route Table
                │   ├── Security List
                │   ├── NSG
                │   └── Gateways (IGW, NAT, SGW, DRG)
                ├── Compute Instance
                ├── Block Volume
                └── Object Storage Bucket
```

---

## 1. Tenancy

A tenancy is the top-level OCI account for your organization. It has a globally
unique **OCID** (Oracle Cloud Identifier). All resources you create belong to
your tenancy, regardless of which region they are in.

The tenancy OCID is required for Terraform authentication and appears in every
`provider "oci"` block.

---

## 2. Region

A region is a geographically distinct location where OCI operates data centers.
Regions are independent — a failure in one region does not affect others.

Relevant regions for this project:

| Region identifier | Location |
|---|---|
| `ap-tokyo-1` | Tokyo, Japan |
| `ap-osaka-1` | Osaka, Japan |
| `ap-singapore-1` | Singapore |
| `us-ashburn-1` | Ashburn, Virginia (US East) |
| `eu-frankfurt-1` | Frankfurt, Germany |

In Terraform, the region is set in the `provider` block. Each environment
directory in this project targets a specific region:

```hcl
# environments/tokyo/main.tf
provider "oci" {
  region = "ap-tokyo-1"
  # ...
}

# environments/osaka/main.tf
provider "oci" {
  region = "ap-osaka-1"
  # ...
}
```

This is the core of multi-region IaC: the same module code runs in both regions,
but each environment's provider block points to a different region.

---

## 3. Availability Domain (AD)

Each region contains one to three Availability Domains. An AD is a physically
separate data center with its own power, cooling, and network infrastructure.
ADs within a region are connected by a low-latency, high-bandwidth internal network.

- Tokyo (`ap-tokyo-1`): 1 AD
- Osaka (`ap-osaka-1`): 1 AD
- US East (`us-ashburn-1`): 3 ADs

For high availability, distribute instances across multiple ADs. Block Volumes
are AD-scoped — a volume in AD-1 can only be attached to an instance in AD-1.

```hcl
# Retrieve all ADs in the current region
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

# Reference the first AD by index
resource "oci_core_instance" "vm" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  # AD name format: "aBCD:AP-TOKYO-1-AD-1"
}
```

---

## 4. Compartment

A compartment is a logical container for organizing and isolating resources.
It is the primary unit of access control in OCI — IAM policies grant permissions
at the compartment level.

```
Tenancy (root compartment)
├── Production/
│   ├── Network/      ← VCNs, subnets, gateways
│   └── Compute/      ← VMs, block volumes
├── Development/
└── Shared-Services/  ← Object Storage, DNS
```

Every Terraform resource requires a `compartment_id`. Resources in different
compartments can still communicate if they are in the same VCN or connected via DRG.

```hcl
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id  # OCID of the target compartment
  # ...
}
```

---

## 5. OCID — Oracle Cloud Identifier

Every OCI resource has a globally unique OCID. Terraform uses OCIDs to reference
resources in API calls and to store resource identity in the state file.

OCID format:
```
ocid1.<resource_type>.<realm>.<region>.<unique_id>

Examples:
ocid1.vcn.oc1.ap-tokyo-1.aaaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
ocid1.drg.oc1.ap-osaka-1.aaaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
ocid1.compartment.oc1..aaaaaaaaXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Note: compartment OCIDs have an empty region field (the `..` before the unique ID)
because compartments are tenancy-scoped, not region-scoped.

---

## 6. Virtual Cloud Network (VCN)

A VCN is your private, isolated network on OCI — equivalent to AWS VPC or
Azure VNet. All compute instances, databases, and load balancers live inside a VCN.

### CIDR Planning for Multi-Region

When deploying to multiple regions, each VCN must have a **non-overlapping CIDR block**.
Overlapping CIDRs prevent DRG peering and cause routing ambiguity.

This project uses:
- Tokyo VCN: `10.0.0.0/16` (65,536 addresses)
- Osaka VCN: `10.1.0.0/16` (65,536 addresses)

```hcl
# Tokyo
resource "oci_core_vcn" "main" {
  cidr_blocks  = ["10.0.0.0/16"]
  display_name = "myproject-dev-tky-vcn"
}

# Osaka
resource "oci_core_vcn" "main" {
  cidr_blocks  = ["10.1.0.0/16"]
  display_name = "myproject-dev-osk-vcn"
}
```

### DNS Label

The `dns_label` on a VCN and its subnets enables internal DNS resolution.
Instances get hostnames like `<hostname>.<subnet_dns_label>.<vcn_dns_label>.oraclevcn.com`.

```hcl
resource "oci_core_vcn" "main" {
  dns_label = "myprojectdevtky"  # alphanumeric only, max 15 chars
}
```

---

## 7. Subnets

A subnet is a subdivision of the VCN's CIDR block. Every VNIC (network interface)
attached to an instance belongs to exactly one subnet.

### Public vs Private Subnet

| | Public Subnet | Private Subnet |
|---|---|---|
| Public IP on VNIC | Allowed | Blocked |
| Internet access | Bidirectional via IGW | Outbound only via NAT |
| Use case | Bastion/jump-box, load balancer | Application servers, databases |

```hcl
# Public subnet — VNICs may have public IPs
resource "oci_core_subnet" "public" {
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
}

# Private subnet — VNICs never get public IPs
resource "oci_core_subnet" "private" {
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
}
```

---

## 8. Gateways

OCI provides four types of gateways, each serving a distinct traffic path.

### Internet Gateway (IGW)

Enables **bidirectional** communication between the VCN and the public internet.
Required for any instance that needs a public IP (e.g. a Windows bastion/jump-box).

```
Public Subnet Instance ←──► Internet Gateway ←──► Internet
```

```hcl
resource "oci_core_internet_gateway" "main" {
  vcn_id  = oci_core_vcn.main.id
  enabled = true
}
```

### NAT Gateway

Enables **outbound-only** internet access for private subnet instances.
The instance can initiate connections to the internet (e.g. Windows Update,
downloading packages) but the internet cannot initiate connections inbound.

```
Private Subnet Instance ──► NAT Gateway ──► Internet
                         (no inbound path)
```

```hcl
resource "oci_core_nat_gateway" "main" {
  vcn_id        = oci_core_vcn.main.id
  block_traffic = false  # false = allow outbound; true = block all (maintenance mode)
}
```

### Service Gateway (SGW)

Enables private subnet instances to reach **OCI managed services** (Object Storage,
Streaming, Vault, etc.) over OCI's internal backbone network — without traversing
the public internet.

Benefits over using NAT Gateway for OCI services:
- No egress bandwidth charges
- Traffic never leaves OCI's network (better security posture)
- Lower latency

```hcl
data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "main" {
  vcn_id = oci_core_vcn.main.id
  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}
```

### Dynamic Routing Gateway (DRG)

The DRG is OCI's **hub router** for connectivity beyond the VCN:

| Connection type | What it enables |
|---|---|
| VCN attachment | Connects the DRG to a VCN |
| Remote Peering Connection (RPC) | Cross-region VCN-to-VCN (Tokyo ↔ Osaka) |
| IPSec VPN | On-premises connectivity over the internet |
| FastConnect | Dedicated private circuit to on-premises |

```
Tokyo VCN ──► Tokyo DRG ──── RPC ──── Osaka DRG ◄── Osaka VCN
```

```hcl
# Create the DRG
resource "oci_core_drg" "main" {
  compartment_id = var.compartment_id
}

# Attach the DRG to the VCN
resource "oci_core_drg_attachment" "main" {
  drg_id = oci_core_drg.main.id
  network_details {
    id   = oci_core_vcn.main.id
    type = "VCN"
  }
}
```

After attaching the DRG, add route rules pointing cross-region CIDRs to the DRG:

```hcl
route_rules {
  destination       = "10.1.0.0/16"  # Osaka VCN CIDR
  destination_type  = "CIDR_BLOCK"
  network_entity_id = oci_core_drg.main.id
}
```

---

## 9. DHCP Options

DHCP Options configure the DNS behavior for all instances in a subnet.
OCI provides two built-in resolver types:

| Type | Behavior |
|---|---|
| `VcnLocalPlusInternet` | Resolves internal OCI hostnames AND public DNS names |
| `CustomDnsServer` | Forwards all DNS queries to your own DNS server |

This project uses `VcnLocalPlusInternet` so Windows instances can resolve both
internal hostnames (e.g. `server1.private.myprojectdevtky.oraclevcn.com`) and
public names (e.g. `windowsupdate.microsoft.com`).

```hcl
resource "oci_core_dhcp_options" "main" {
  vcn_id = oci_core_vcn.main.id

  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }

  options {
    type                = "SearchDomain"
    search_domain_names = ["corp.example.com"]
  }
}
```

Subnets reference the DHCP Options object:

```hcl
resource "oci_core_subnet" "private" {
  dhcp_options_id = oci_core_dhcp_options.main.id
  # ...
}
```

---

## 10. Route Tables

A route table is a set of rules that determine where network traffic is forwarded.
Each subnet is associated with exactly one route table.

### Route Table for Public Subnet

```hcl
resource "oci_core_route_table" "public" {
  vcn_id = oci_core_vcn.main.id

  # Default route: all internet-bound traffic goes through the IGW
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }

  # Cross-region traffic goes through the DRG
  route_rules {
    destination       = "10.1.0.0/16"   # Osaka VCN
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.main.id
  }
}
```

### Route Table for Private Subnet

```hcl
resource "oci_core_route_table" "private" {
  vcn_id = oci_core_vcn.main.id

  # Default route: outbound internet via NAT (no inbound)
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  # OCI services via Service Gateway (no internet hop)
  route_rules {
    destination       = "all-nrt-services-in-oracle-services-network"
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }

  # Cross-region traffic via DRG
  route_rules {
    destination       = "10.1.0.0/16"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.main.id
  }
}
```

---

## 11. Security List vs Network Security Group (NSG)

OCI has two complementary firewall mechanisms. Understanding the difference is
important for designing a correct security model.

### Security List

A Security List is attached to a **subnet** and applies to all VNICs in that subnet.
Rules are evaluated for every packet entering or leaving any instance in the subnet.

```hcl
resource "oci_core_security_list" "windows" {
  vcn_id = oci_core_vcn.main.id

  ingress_security_rules {
    protocol = "6"   # TCP
    source   = "203.0.113.0/28"
    tcp_options {
      min = 3389   # RDP
      max = 3389
    }
  }
}
```

### Network Security Group (NSG)

An NSG is attached to individual **VNICs** (not subnets). This allows different
instances in the same subnet to have different security rules.

The key advantage of NSGs: rules can reference **another NSG** as the source or
destination, instead of a CIDR block. This is more robust than IP-based rules
because it remains correct even when instances are replaced and get new IPs.

```hcl
# Allow RDP from any VNIC in the bastion NSG — no IP address needed
resource "oci_core_network_security_group_security_rule" "app_rdp" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.bastion.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 3389
      max = 3389
    }
  }
}
```

### Comparison

| Aspect | Security List | NSG |
|---|---|---|
| Attached to | Subnet | VNIC (instance) |
| Scope | All instances in subnet | Only tagged instances |
| Source/destination | CIDR only | CIDR or another NSG |
| Granularity | Coarse | Fine |
| Best for | Broad subnet-level rules | Instance-role-specific rules |

**Best practice:** Use Security Lists for broad baseline rules (e.g. allow ICMP
within VCN), and NSGs for role-specific rules (e.g. app servers accept RDP only
from bastion NSG).

### Protocol numbers

OCI uses IANA protocol numbers in security rules:

| Number | Protocol |
|---|---|
| `"1"` | ICMP |
| `"6"` | TCP |
| `"17"` | UDP |
| `"all"` | All protocols |

---

## 12. Windows-Specific Ports

This project targets Windows Server instances. The relevant ports are:

| Port | Protocol | Purpose |
|---|---|---|
| 3389 | TCP | RDP — Remote Desktop Protocol (primary management) |
| 5985 | TCP | WinRM HTTP — Windows Remote Management (Ansible, automation) |
| 5986 | TCP | WinRM HTTPS — encrypted WinRM |
| 445 | TCP | SMB — Windows file sharing |
| ICMP type 3 | ICMP | Destination Unreachable — required for path MTU discovery |
| ICMP type 8 | ICMP | Echo Request (ping) — connectivity diagnostics |

---

## 13. OCI Authentication for Terraform

Terraform calls OCI REST APIs on your behalf. It authenticates using an
**API signing key** — an RSA key pair where:
- The private key stays on your machine (never shared)
- The public key is uploaded to your OCI user profile
- OCI verifies API requests are signed with the matching private key

```bash
# Generate the key pair
openssl genrsa -out ~/.oci/oci_api_key.pem 4096
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

Upload `oci_api_key_public.pem` to:
**OCI Console → Profile → User Settings → API Keys → Add API Key**

The fingerprint shown after upload is the MD5 hash of the public key. It uniquely
identifies which key was used to sign a request.

```hcl
provider "oci" {
  tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaa..."
  user_ocid        = "ocid1.user.oc1..aaaaaa..."
  fingerprint      = "ab:cd:ef:12:34:56:..."   # from OCI Console
  private_key_path = "~/.oci/oci_api_key.pem"
  region           = "ap-tokyo-1"
}
```

**Next:** [Guide 3 — Project Walkthrough](./03-project-walkthrough.md)
