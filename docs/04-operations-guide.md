# Guide 4: Operations — Setup, Deploy, and Day-2

## Prerequisites

| Tool | Minimum version | Install | Verify |
|---|---|---|---|
| Terraform | 1.5.0 | https://developer.hashicorp.com/terraform/install | `terraform version` |
| OCI CLI | 3.x (optional) | `pip install oci-cli` | `oci --version` |
| OpenSSL | any | OS package manager | `openssl version` |
| Git | any | OS package manager | `git --version` |

---

## Step 1 — Create an OCI API Signing Key

Terraform authenticates to OCI by signing every API request with an RSA private key.
The matching public key is registered in your OCI user profile. OCI verifies the
signature on each request to confirm it came from an authorized user.

```bash
# Create the OCI config directory
mkdir -p ~/.oci

# Generate a 4096-bit RSA private key
openssl genrsa -out ~/.oci/oci_api_key.pem 4096

# Restrict permissions — the key must not be readable by other users
chmod 600 ~/.oci/oci_api_key.pem

# Derive the public key from the private key
openssl rsa -pubout \
  -in  ~/.oci/oci_api_key.pem \
  -out ~/.oci/oci_api_key_public.pem
```

Upload the public key to OCI:
1. OCI Console → top-right avatar → **User Settings**
2. **API Keys** → **Add API Key**
3. Select **Paste a public key**, paste the full content of `oci_api_key_public.pem`
4. Click **Add** — OCI displays the **Fingerprint** (MD5 hash of the public key)
5. Copy the fingerprint — you will need it in `terraform.tfvars`

---

## Step 2 — Collect Required OCIDs

You need three OCIDs before you can fill in `terraform.tfvars`.

| Value | Where to find it in OCI Console |
|---|---|
| `tenancy_ocid` | Profile menu (top-right) → **Tenancy** → copy OCID |
| `user_ocid` | Profile menu → **User Settings** → copy OCID |
| `compartment_id` | **Identity & Security** → **Compartments** → click your compartment → copy OCID |

---

## Step 3 — Configure terraform.tfvars

Each environment has a `terraform.tfvars.example` file. Copy it and fill in your values.

```bash
# Tokyo
cd environments/tokyo
cp terraform.tfvars.example terraform.tfvars

# Osaka
cd environments/osaka
cp terraform.tfvars.example terraform.tfvars
```

Key values to fill in:

```hcl
# OCI authentication
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaa..."
user_ocid        = "ocid1.user.oc1..aaaaaa..."
fingerprint      = "ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90"
private_key_path = "/home/yourname/.oci/oci_api_key.pem"  # absolute path

# Project
project_name   = "myproject"    # lowercase letters and numbers only
environment    = "dev"
compartment_id = "ocid1.compartment.oc1..aaaaaa..."
owner_tag      = "devops-team@example.com"

# Network access control
# Use your on-premises IP range or VPN CIDR.
# Use x.x.x.x/32 to restrict to a single IP address.
management_cidr   = "203.0.113.10/32"
dns_search_domain = "corp.example.com"
```

`terraform.tfvars` is listed in `.gitignore` and must never be committed to Git.
It contains credentials and sensitive network information.

---

## Step 4 — Deploy Tokyo

```bash
cd environments/tokyo

# Download the OCI provider plugin (~100 MB, cached after first run)
# Also initializes the backend and reads .terraform.lock.hcl
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Finding oracle/oci versions matching "~> 8.12.0"...
- Installing oracle/oci v8.12.0...
Terraform has been successfully initialized!
```

```bash
# Validate configuration syntax (no API calls)
terraform validate
# Success! The configuration is valid.

# Preview what will be created — READ THIS CAREFULLY before applying
terraform plan
```

The plan output lists every resource Terraform will create. For this project,
expect approximately 18 resources:

```
Plan: 18 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + vcn_id           = (known after apply)
  + drg_id           = (known after apply)
  + bastion_nsg_id   = (known after apply)
  ...
```

If the plan looks correct:

```bash
# Deploy — Terraform will ask "Do you want to perform these actions? yes/no"
terraform apply
```

After apply completes (typically 2–4 minutes):

```
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.

Outputs:

vcn_id           = "ocid1.vcn.oc1.ap-tokyo-1.aaaa..."
public_subnet_id = "ocid1.subnet.oc1.ap-tokyo-1.aaaa..."
drg_id           = "ocid1.drg.oc1.ap-tokyo-1.aaaa..."
bastion_nsg_id   = "ocid1.networksecuritygroup.oc1.ap-tokyo-1.aaaa..."
...
```

---

## Step 5 — Deploy Osaka

```bash
cd environments/osaka
terraform init
terraform validate
terraform plan
terraform apply
```

The process is identical to Tokyo. Osaka uses the same module with different
parameters (`region_key = "osk"`, `vcn_cidr = "10.1.0.0/16"`, etc.).

---

## Step 6 — Connect Tokyo ↔ Osaka via DRG Remote Peering

After both regions are deployed, the DRGs exist but are not yet connected.
Traffic between `10.0.0.0/16` (Tokyo) and `10.1.0.0/16` (Osaka) will be
dropped until a Remote Peering Connection (RPC) is established.

### Retrieve the DRG OCIDs

```bash
# Tokyo DRG OCID
cd environments/tokyo
terraform output drg_id
# ocid1.drg.oc1.ap-tokyo-1.aaaa...

# Osaka DRG OCID
cd environments/osaka
terraform output drg_id
# ocid1.drg.oc1.ap-osaka-1.aaaa...
```

### Create the Remote Peering Connection

1. OCI Console → **Networking** → **Dynamic Routing Gateways**
2. Select the **Tokyo DRG** → **Remote Peering Connections** → **Create RPC**
3. Name: `tokyo-to-osaka-rpc`
4. After creation, click **Establish Connection**
5. Peer Region: `Japan West (Osaka)` → `ap-osaka-1`
6. Peer DRG OCID: paste the Osaka DRG OCID
7. Click **Establish Connection** — status changes to `PEERED` within ~30 seconds

### Why routing works automatically

The route tables were already configured with DRG rules during `terraform apply`:

```hcl
# In Tokyo's private route table
route_rules {
  destination       = "10.1.0.0/16"   # Osaka VCN
  destination_type  = "CIDR_BLOCK"
  network_entity_id = oci_core_drg.main.id
}
```

As soon as the RPC is established, packets destined for `10.1.x.x` from Tokyo
are forwarded to the Tokyo DRG, traverse the RPC, and arrive at the Osaka DRG,
which routes them to the correct Osaka subnet.

### Verify connectivity

From a Windows VM in the Tokyo private subnet:
```powershell
# Ping an Osaka private subnet IP
ping 10.1.2.10

# Test RDP port reachability
Test-NetConnection -ComputerName 10.1.2.10 -Port 3389
```

---

## Day-2 Operations

### Viewing current state

```bash
# List all resources tracked in state
terraform state list

# Show full details of a specific resource
terraform state show module.networking.oci_core_vcn.main

# Show all output values
terraform output
```

### Making a change (e.g. adding a new NSG rule)

```bash
# 1. Edit the .tf file
vim modules/networking/main.tf

# 2. Format the file
terraform fmt -recursive

# 3. Validate syntax
terraform validate

# 4. Preview the change — verify only the intended resource is affected
terraform plan

# 5. Apply
terraform apply
```

### Saving a plan for production changes

For production, always save the plan to a file and apply that exact plan.
This prevents any drift between the time you reviewed the plan and the time
you applied it.

```bash
# Save the plan
terraform plan -out=tfplan.binary

# Review the saved plan (human-readable)
terraform show tfplan.binary

# Apply exactly the saved plan — no confirmation prompt
terraform apply tfplan.binary
```

### Destroying a single region

```bash
cd environments/tokyo
terraform destroy
# Terraform will show a destroy plan and ask for confirmation
```

### Destroying a specific resource without touching others

```bash
# Remove only the DRG and its attachment
terraform destroy \
  -target=module.networking.oci_core_drg_attachment.main \
  -target=module.networking.oci_core_drg.main
```

Note: always destroy the attachment before the DRG, or use both `-target` flags
together so Terraform handles the order.

---

## Remote State Setup

Local state is acceptable for learning but must not be used in a team environment.
Set up remote state on OCI Object Storage before sharing the project with others.

### Create the state bucket (one-time)

```bash
# Using OCI CLI
oci os bucket create \
  --compartment-id <compartment_ocid> \
  --name "tfstate-myproject" \
  --versioning Enabled \
  --region ap-tokyo-1
```

Or create it manually in OCI Console: **Object Storage** → **Create Bucket**
with versioning enabled.

### Create Pre-Authenticated Requests (PAR)

A PAR is a time-limited URL that grants read/write access to a specific object
without requiring OCI credentials. Terraform uses it as the state backend URL.

1. OCI Console → **Object Storage** → `tfstate-myproject`
2. **Pre-Authenticated Requests** → **Create Pre-Authenticated Request**
3. Settings:
   - Access type: **Permit object reads and writes**
   - Object name: `tokyo/terraform.tfstate`
   - Expiration: 1 year (or longer)
4. Copy the generated URL immediately — it is shown only once
5. Repeat for `osaka/terraform.tfstate`

### Enable the backend

Uncomment the `backend "http"` block in `environments/tokyo/main.tf`:

```hcl
terraform {
  backend "http" {
    address       = "https://objectstorage.ap-tokyo-1.oraclecloud.com/p/<PAR_TOKEN>/n/<NAMESPACE>/b/tfstate-myproject/o/tokyo/terraform.tfstate"
    update_method = "PUT"
  }
}
```

Migrate existing local state to remote:

```bash
terraform init -migrate-state
# Terraform will ask: "Do you want to copy existing state to the new backend? yes"
```

After migration, `terraform.tfstate` on your local machine is no longer used.
All state reads and writes go to OCI Object Storage.

---

## Troubleshooting

| Error message | Likely cause | Fix |
|---|---|---|
| `401-NotAuthenticated` | Wrong fingerprint or key path | Verify `fingerprint` matches what OCI Console shows; check `private_key_path` exists |
| `404-NotAuthorizedOrNotFound` | Wrong compartment OCID or missing IAM policy | Verify `compartment_id`; check IAM policy below |
| `409-Conflict` on VCN | A VCN with the same display name already exists | Change `project_name` or `environment` in tfvars |
| `dns_label` validation error | Combined label exceeds 15 chars or contains invalid chars | Shorten `project_name`; ensure `region_key` is 2–6 lowercase letters |
| `Error locking state` | A previous apply crashed without releasing the lock | Run `terraform force-unlock <LOCK_ID>` (ID shown in the error) |
| `Error: Invalid function argument` on `cidrhost` | `management_cidr` is not a valid CIDR | Use format `x.x.x.x/prefix`, e.g. `203.0.113.10/32` |

### Required IAM Policy

The OCI user or group running Terraform needs these policies in the target compartment:

```
Allow group <terraform-group> to manage virtual-network-family in compartment <name>
Allow group <terraform-group> to manage drgs in compartment <name>
Allow group <terraform-group> to read objectstorage-namespaces in tenancy
```

If using a separate compartment for Object Storage state:
```
Allow group <terraform-group> to manage objects in compartment <state-compartment>
  where target.bucket.name = 'tfstate-myproject'
```

---

## Adding a Third Region

The module-based design makes adding a new region straightforward.

1. Create a new environment directory:

```bash
mkdir -p environments/singapore
```

2. Copy the Tokyo environment as a template:

```bash
cp environments/tokyo/main.tf       environments/singapore/main.tf
cp environments/tokyo/variables.tf  environments/singapore/variables.tf
cp environments/tokyo/outputs.tf    environments/singapore/outputs.tf
cp environments/tokyo/terraform.tfvars.example environments/singapore/terraform.tfvars.example
```

3. Edit `environments/singapore/main.tf` — change three things:

```hcl
# Provider: change region
provider "oci" {
  region = "ap-singapore-1"   # was ap-tokyo-1
}

# common_tags: change region label
locals {
  common_tags = {
    region = "ap-singapore-1"  # was ap-tokyo-1
  }
}

# Module call: change region-specific values
module "networking" {
  region_key          = "sgp"           # was "tky"
  vcn_cidr            = "10.2.0.0/16"  # was "10.0.0.0/16" — must not overlap
  public_subnet_cidr  = "10.2.1.0/24"
  private_subnet_cidr = "10.2.2.0/24"
  cross_region_cidrs  = ["10.0.0.0/16", "10.1.0.0/16"]  # Tokyo + Osaka
}
```

4. Deploy:

```bash
cd environments/singapore
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

5. Update Tokyo and Osaka to add Singapore's CIDR to their `cross_region_cidrs`:

```hcl
# environments/tokyo/main.tf
cross_region_cidrs = ["10.1.0.0/16", "10.2.0.0/16"]  # Osaka + Singapore

# environments/osaka/main.tf
cross_region_cidrs = ["10.0.0.0/16", "10.2.0.0/16"]  # Tokyo + Singapore
```

```bash
cd environments/tokyo && terraform apply
cd environments/osaka && terraform apply
```

6. Create RPC connections: Tokyo DRG ↔ Singapore DRG, Osaka DRG ↔ Singapore DRG.

No changes to the networking module are needed. The module already supports
multiple cross-region CIDRs via the `dynamic` block.

---

## Reference

| Resource | URL |
|---|---|
| OCI Terraform Provider docs | https://registry.terraform.io/providers/oracle/oci/latest/docs |
| OCI Networking overview | https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/overview.htm |
| DRG and Remote Peering | https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/remoteVCNpeering.htm |
| OCI Regions list | https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm |
| Terraform language reference | https://developer.hashicorp.com/terraform/language |
| Terraform CLI reference | https://developer.hashicorp.com/terraform/cli |
| OCI IAM policies | https://docs.oracle.com/en-us/iaas/Content/Identity/Concepts/policygetstarted.htm |
