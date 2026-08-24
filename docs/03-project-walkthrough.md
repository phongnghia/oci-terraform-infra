# Guide 3: Project Walkthrough

This guide walks through every file in the project, explains the design decisions,
and shows how the pieces connect to each other.

---

## Project Structure

```
oci-terraform-infra/
├── modules/
│   └── networking/          # Reusable module — one VCN stack
│       ├── main.tf           # All resources
│       ├── variables.tf      # Inputs
│       └── outputs.tf        # Outputs
├── environments/
│   ├── tokyo/               # ap-tokyo-1 deployment
│   │   ├── main.tf           # Calls the networking module
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── osaka/               # ap-osaka-1 deployment
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
└── docs/
```

---

## How Multi-Region Works in This Project

The central design principle is **one module, multiple environments**.

```
modules/networking/main.tf
        │
        ├── called by environments/tokyo/main.tf
        │     provider region = "ap-tokyo-1"
        │     vcn_cidr        = "10.0.0.0/16"
        │     region_key      = "tky"
        │
        └── called by environments/osaka/main.tf
              provider region = "ap-osaka-1"
              vcn_cidr        = "10.1.0.0/16"
              region_key      = "osk"
```

The networking module contains zero hardcoded region-specific values. Every
region-specific detail (CIDR, region key, cross-region peer CIDRs) is passed
in as a variable. This means:

- A bug fix or new feature in the module is applied to both regions by running
  `terraform apply` in each environment directory
- Adding a third region (e.g. Singapore) requires only a new environment directory
  — no changes to the module itself

### State isolation

Each environment directory has its own state file. Tokyo's state and Osaka's state
are completely independent. Destroying Tokyo does not affect Osaka.

```
environments/tokyo/terraform.tfstate   ← tracks Tokyo resources only
environments/osaka/terraform.tfstate   ← tracks Osaka resources only
```

---

## Architecture Diagram

```
                         Internet
                            │
           ┌────────────────┴────────────────┐
           │                                 │
    ┌──────▼──────┐                   ┌──────▼──────┐
    │  Tokyo IGW  │                   │  Osaka IGW  │
    └──────┬──────┘                   └──────┬──────┘
           │                                 │
  ┌────────▼──────────────┐       ┌──────────▼────────────┐
  │  Tokyo VCN            │       │  Osaka VCN            │
  │  10.0.0.0/16          │       │  10.1.0.0/16          │
  │                       │       │                       │
  │  ┌─────────────────┐  │       │  ┌─────────────────┐  │
  │  │ Public Subnet   │  │       │  │ Public Subnet   │  │
  │  │ 10.0.1.0/24     │  │       │  │ 10.1.1.0/24     │  │
  │  │ [Windows Bastion│  │       │  │ [Windows Bastion│  │
  │  │  bastion-nsg]   │  │       │  │  bastion-nsg]   │  │
  │  └─────────────────┘  │       │  └─────────────────┘  │
  │                       │       │                       │
  │  ┌─────────────────┐  │       │  ┌─────────────────┐  │
  │  │ Private Subnet  │  │       │  │ Private Subnet  │  │
  │  │ 10.0.2.0/24     │  │       │  │ 10.1.2.0/24     │  │
  │  │ [Windows App VMs│  │       │  │ [Windows App VMs│  │
  │  │  app-nsg]       │  │       │  │  app-nsg]       │  │
  │  └─────────────────┘  │       │  └─────────────────┘  │
  │                       │       │                       │
  │  NAT GW → Internet    │       │  NAT GW → Internet    │
  │  SGW → OCI Services   │       │  SGW → OCI Services   │
  │  DRG ─────────────────┼──RPC──┼──── DRG              │
  └───────────────────────┘       └───────────────────────┘
         Tokyo ↔ Osaka via DRG Remote Peering Connection
```

---

## Walking Through modules/networking/main.tf

### Data source: OCI services

```hcl
data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}
```

This data source retrieves the CIDR block and service ID for the "All Services"
bundle in the current region. Using a data source instead of hardcoding the
service CIDR means the code works correctly in any OCI region without modification.

The result is used in two places:
1. The Service Gateway `services` block — to specify which services are reachable
2. The private route table — to route service-bound traffic to the SGW

### VCN and DNS label

```hcl
resource "oci_core_vcn" "main" {
  cidr_blocks = [var.vcn_cidr]
  dns_label   = "${var.project_name}${var.environment}${var.region_key}"
}
```

The `dns_label` must be alphanumeric and at most 15 characters. Concatenating
`project_name + environment + region_key` (e.g. `myprojectdevtky`) produces a
unique, human-readable label per region. The validation on `region_key` (2–6
lowercase letters) prevents the label from exceeding the limit.

### DHCP Options

```hcl
resource "oci_core_dhcp_options" "main" {
  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }
  options {
    type                = "SearchDomain"
    search_domain_names = [var.dns_search_domain]
  }
}
```

`VcnLocalPlusInternet` means OCI's resolver handles both internal VCN hostnames
and public DNS. The `SearchDomain` option appends your corporate domain to
unqualified hostnames — so `ping fileserver` resolves as
`fileserver.corp.example.com` on Windows instances.

### Gateway ordering

The Internet Gateway is declared after the route tables in the file, but Terraform
does not care about declaration order — it builds the dependency graph from
references. The public route table references `oci_core_internet_gateway.main.id`,
so Terraform knows to create the IGW before the route table.

### Dynamic route rules for cross-region CIDRs

```hcl
dynamic "route_rules" {
  for_each = var.cross_region_cidrs
  content {
    destination       = route_rules.value
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.main.id
  }
}
```

`cross_region_cidrs` is a list of CIDRs that should be routed through the DRG.
Using a `dynamic` block means:
- If the list is empty (no peering needed), no DRG route rules are created
- If you add a third region later, just add its CIDR to the list — no structural
  code change required

For Tokyo, `cross_region_cidrs = ["10.1.0.0/16"]` (Osaka's VCN).
For Osaka, `cross_region_cidrs = ["10.0.0.0/16"]` (Tokyo's VCN).

### DRG and attachment

```hcl
resource "oci_core_drg" "main" {
  compartment_id = var.compartment_id
}

resource "oci_core_drg_attachment" "main" {
  drg_id = oci_core_drg.main.id
  network_details {
    id   = oci_core_vcn.main.id
    type = "VCN"
  }
}
```

The DRG itself is a standalone resource. The attachment is a separate resource
that binds the DRG to a specific VCN. This separation allows one DRG to be
attached to multiple VCNs (hub-and-spoke topology), though this project uses
one DRG per VCN.

After both DRGs are created, a **Remote Peering Connection (RPC)** is established
between them. The RPC is not managed by Terraform in this project because it
requires both DRG OCIDs to exist first and involves a cross-region operation.
See Guide 4 for the manual steps.

### Security List — why both Security List and NSG?

The project uses both mechanisms intentionally:

- **Security List** (`oci_core_security_list.windows`): broad subnet-level rules
  that apply to every instance in the subnet. Covers baseline Windows ports
  (RDP, WinRM, SMB, ICMP) from the management CIDR and within the VCN.

- **NSG** (`bastion-nsg`, `app-nsg`): role-specific rules. The app NSG allows
  RDP only from the bastion NSG — not from any CIDR. This means even if someone
  adds a new instance to the public subnet without the bastion NSG, it cannot
  RDP into app servers.

The two layers work together: a packet must pass both the Security List check
(subnet level) and the NSG check (VNIC level) to be allowed.

### NSG-to-NSG reference

```hcl
resource "oci_core_network_security_group_security_rule" "app_ingress_rdp_from_bastion" {
  source      = oci_core_network_security_group.bastion.id
  source_type = "NETWORK_SECURITY_GROUP"
}
```

This rule says: "allow RDP from any VNIC that has the bastion NSG attached."
If the bastion instance is terminated and a new one is created (with a different
private IP), this rule still works correctly — no IP address to update.

---

## Walking Through environments/tokyo/main.tf

### Provider block

```hcl
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = "ap-tokyo-1"   # ← hardcoded, not a variable
}
```

The region is hardcoded in the provider block, not taken from a variable. This
is intentional: the environment directory is named `tokyo` and is exclusively
for the Tokyo region. Making the region a variable would allow accidentally
deploying Tokyo's configuration to Osaka, which would create CIDR conflicts.

### common_tags local

```hcl
locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    region      = "ap-tokyo-1"
    managed-by  = "terraform"
    owner       = var.owner_tag
  }
}
```

Every resource created by the networking module receives these tags via
`merge(var.common_tags, { ... })`. Tags serve multiple purposes:
- **Cost allocation**: filter OCI Cost Analysis by `project` or `environment`
- **Discoverability**: search resources in OCI Console by tag
- **Automation**: scripts can target resources by `managed-by = terraform`
- **Accountability**: `owner` identifies who is responsible

### Module call

```hcl
module "networking" {
  source = "../../modules/networking"

  compartment_id      = var.compartment_id
  project_name        = var.project_name
  environment         = var.environment
  region_key          = "tky"
  vcn_cidr            = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  management_cidr     = var.management_cidr
  dns_search_domain   = var.dns_search_domain
  cross_region_cidrs  = ["10.1.0.0/16"]
  common_tags         = local.common_tags
}
```

The `source` path is relative to the environment directory. Terraform resolves
it to `oci-terraform-infra/modules/networking/`.

`region_key = "tky"` is hardcoded here (not a variable) for the same reason
the provider region is hardcoded — this environment is exclusively for Tokyo.

---

## File Naming Conventions

| File | Purpose |
|---|---|
| `main.tf` | Resource definitions and module calls |
| `variables.tf` | Input variable declarations with types, descriptions, validations |
| `outputs.tf` | Output value declarations |
| `terraform.tfvars.example` | Template showing all required variables (committed to Git) |
| `terraform.tfvars` | Actual values including secrets (gitignored, never committed) |
| `.terraform.lock.hcl` | Provider version lock file (committed to Git) |
| `terraform.tfstate` | State file (gitignored, stored remotely in production) |

---

## Dependency Flow

```
environments/tokyo/main.tf
    │
    └── module "networking"
            │
            ├── data "oci_core_services"          (read-only, no dependencies)
            │
            ├── oci_core_vcn.main                 (no dependencies)
            │
            ├── oci_core_dhcp_options.main         depends on: vcn
            ├── oci_core_internet_gateway.main     depends on: vcn
            ├── oci_core_nat_gateway.main          depends on: vcn
            ├── oci_core_service_gateway.main      depends on: vcn, data source
            ├── oci_core_drg.main                  (no dependencies)
            ├── oci_core_drg_attachment.main       depends on: drg, vcn
            │
            ├── oci_core_route_table.public        depends on: vcn, igw, drg
            ├── oci_core_route_table.private       depends on: vcn, nat, sgw, drg
            │
            ├── oci_core_security_list.windows     depends on: vcn
            │
            ├── oci_core_subnet.public             depends on: vcn, dhcp, rt_public, sl
            ├── oci_core_subnet.private            depends on: vcn, dhcp, rt_private, sl
            │
            ├── oci_core_network_security_group.bastion   depends on: vcn
            ├── oci_core_network_security_group.app       depends on: vcn
            │
            └── NSG rules (6 rules)               depends on: respective NSGs
```

Terraform creates resources in parallel where possible. For example, the DRG,
DHCP Options, Internet Gateway, NAT Gateway, and Service Gateway are all created
in parallel after the VCN is ready.

---

## Key Patterns Used in This Project

### Pattern: region_key for unique naming

```hcl
display_name = "${var.project_name}-${var.environment}-${var.region_key}-vcn"
# Tokyo result: "myproject-dev-tky-vcn"
# Osaka result: "myproject-dev-osk-vcn"
```

Without `region_key`, both regions would try to create resources with the same
display name. While OCI allows duplicate display names (they are not unique
identifiers), it makes the Console confusing. The region key makes every resource
name unique and immediately identifiable.

### Pattern: validation blocks

```hcl
variable "region_key" {
  validation {
    condition     = can(regex("^[a-z]{2,6}$", var.region_key))
    error_message = "region_key must be 2–6 lowercase letters (e.g. tky, osk)."
  }
}
```

Validations run before any API call. They catch configuration mistakes immediately
with a clear error message, rather than letting Terraform make partial API calls
and fail halfway through with a cryptic OCI error.

### Pattern: sensitive variables

```hcl
variable "private_key_path" {
  type      = string
  sensitive = true  # value is redacted in plan/apply output and logs
}
```

Mark any variable that contains or points to a secret as `sensitive`. Terraform
will not print its value in plan output, apply output, or error messages.

### Pattern: merge for tags

```hcl
freeform_tags = merge(var.common_tags, {
  Name = "${var.project_name}-${var.environment}-${var.region_key}-vcn"
  Role = "networking"
})
```

`merge()` combines the common tags (passed in from the environment) with
resource-specific tags. If the same key appears in both maps, the second map
wins — so resource-specific tags can override common tags when needed.

---

## Exercises

1. Trace the full dependency chain for `oci_core_subnet.private`. List every
   resource that must exist before the private subnet can be created.

2. The `cross_region_cidrs` variable is a `list(string)`. What happens if you
   pass an empty list `[]`? Read the `dynamic` block in `main.tf` and explain.

3. Open `environments/osaka/main.tf`. What is different from `environments/tokyo/main.tf`?
   List every difference and explain why each one exists.

4. Add a third environment directory `environments/singapore` that deploys the
   same networking module to `ap-singapore-1` with VCN CIDR `10.2.0.0/16`.
   What files do you need to create? What values change?

**Next:** [Guide 4 — Operations Guide](./04-operations-guide.md)
