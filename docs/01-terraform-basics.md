# Guide 1: Terraform Fundamentals

## What is Terraform?

Terraform is an open-source **Infrastructure as Code (IaC)** tool created by HashiCorp.
Instead of clicking through a cloud console to create resources, you write declarative
configuration files that describe the desired state of your infrastructure. Terraform
then figures out what needs to be created, updated, or deleted to reach that state.

The key word is **declarative**: you describe *what* you want, not *how* to build it.
Terraform handles the sequencing, dependency resolution, and API calls automatically.

```
Traditional approach          IaC approach
─────────────────────         ─────────────────────────────────────
1. Open OCI Console           1. Write .tf files describing resources
2. Click "Create VCN"         2. Run terraform apply
3. Fill in form fields        3. Terraform calls OCI API automatically
4. Click "Create Subnet"      4. Repeat identically in any environment
5. Repeat for every resource
6. Hope you remember steps
   next time
```

---

## Why IaC Matters

### Reproducibility
The same Terraform code produces identical infrastructure every time, in any environment.
Dev, staging, and production are guaranteed to have the same network topology, security
rules, and configuration — no more "it works in dev but not in prod" caused by
infrastructure differences.

### Version Control
Infrastructure changes are tracked in Git just like application code. You can see exactly
who changed what, when, and why. Rolling back a bad infrastructure change is as simple
as reverting a commit.

### Multi-Region Provisioning
This is where IaC truly shines. Without IaC, deploying the same network stack to Tokyo
and Osaka means repeating every manual step twice — and keeping them in sync forever.
With Terraform, you write the logic once in a reusable module, then call that module
from each region's environment directory with different parameters:

```hcl
# Tokyo — calls the same networking module
module "networking" {
  source   = "../../modules/networking"
  region_key = "tky"
  vcn_cidr   = "10.0.0.0/16"
}

# Osaka — same module, different parameters
module "networking" {
  source   = "../../modules/networking"
  region_key = "osk"
  vcn_cidr   = "10.1.0.0/16"
}
```

One module definition, two consistent deployments. Any change to the module
(e.g. adding a new NSG rule) is applied to both regions with a single `terraform apply`
per environment.

### Automation and CI/CD
Terraform integrates naturally into CI/CD pipelines. Every pull request can trigger
`terraform plan` to show reviewers exactly what infrastructure will change before
merging. Merging to main can automatically apply the changes.

### Cost Control
`terraform destroy` tears down an entire environment in one command. Spinning up a
dev environment for testing and destroying it afterward is trivial — no forgotten
resources accumulating cost.

---

## Core Concepts

### Provider

A provider is the plugin that connects Terraform to a specific platform (OCI, AWS, Azure,
Kubernetes, etc.). It translates Terraform resource definitions into API calls.

Providers are versioned and must be declared explicitly. Pinning the version prevents
unexpected breaking changes when a new provider version is released.

```hcl
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      # ~> 8.12.0 means: >= 8.12.0 and < 8.13.0 (patch updates allowed, minor locked)
      version = "~> 8.12.0"
    }
  }
}

# Provider configuration — credentials and target region
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = "ap-tokyo-1"
}
```

For multi-region deployments, you can declare multiple provider aliases:

```hcl
provider "oci" {
  alias  = "tokyo"
  region = "ap-tokyo-1"
  # ... credentials
}

provider "oci" {
  alias  = "osaka"
  region = "ap-osaka-1"
  # ... credentials
}
```

In this project, each region has its own environment directory with its own provider
block — a cleaner approach that keeps state files separate.

### Resource

A resource is a single infrastructure object managed by Terraform. It maps directly
to something that exists on the cloud platform.

```hcl
# Syntax: resource "<provider_resource_type>" "<local_name>" { ... }
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "tokyo-vcn"
}
```

- `oci_core_vcn` — the resource type, defined by the OCI provider
- `main` — a local name used to reference this resource elsewhere in the same module
- The block body contains the resource's configuration arguments

To reference an attribute of this resource from another resource:

```hcl
resource "oci_core_subnet" "public" {
  vcn_id = oci_core_vcn.main.id  # <resource_type>.<local_name>.<attribute>
}
```

### Data Source

A data source reads existing information from the cloud without creating anything.
Use it when you need to look up a value that already exists (an image ID, an
availability domain name, a service CIDR) rather than hardcoding it.

```hcl
# Look up the latest Oracle Linux 8 image for a given shape
data "oci_core_images" "oracle_linux_8" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.E4.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Use the result in a resource
resource "oci_core_instance" "vm" {
  source_details {
    source_id   = data.oci_core_images.oracle_linux_8.images[0].id
    source_type = "image"
  }
}
```

Data sources are prefixed with `data.` when referenced.

### Variable

Variables are the inputs to a Terraform module or environment. They make
configurations reusable and environment-specific values configurable without
modifying the code itself.

```hcl
# Declaration in variables.tf
variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"

  # Validation runs before any API call — fail fast with a clear message
  validation {
    condition     = can(cidrhost(var.vcn_cidr, 0))
    error_message = "vcn_cidr must be a valid CIDR block."
  }
}
```

**How to supply variable values (in order of precedence, highest first):**

1. `-var` flag: `terraform apply -var="vcn_cidr=10.2.0.0/16"`
2. `-var-file` flag: `terraform apply -var-file="prod.tfvars"`
3. `terraform.tfvars` file in the working directory (loaded automatically)
4. `*.auto.tfvars` files (loaded automatically, alphabetical order)
5. `TF_VAR_<name>` environment variables: `export TF_VAR_vcn_cidr="10.2.0.0/16"`
6. Default value in the variable declaration

In this project, `terraform.tfvars` is the standard approach. The `.example` file
is committed to Git as a template; the actual `terraform.tfvars` is gitignored.

### Output

Outputs expose values from a module or environment after `terraform apply` completes.
They serve two purposes:

1. **Display information** to the operator (IP addresses, OCIDs, connection strings)
2. **Pass values between modules** — a child module's outputs become inputs to the
   parent module

```hcl
# In modules/networking/outputs.tf
output "drg_id" {
  description = "OCID of the DRG — needed for cross-region peering"
  value       = oci_core_drg.main.id
}

# In environments/tokyo/outputs.tf — re-export the module output
output "drg_id" {
  value = module.networking.drg_id
}
```

After apply:
```bash
terraform output drg_id
# ocid1.drg.oc1.ap-tokyo-1.aaaa...
```

### Local Value

Locals are computed values defined within a module. Unlike variables, they cannot
be overridden from outside — they are internal calculations.

```hcl
locals {
  # Build a consistent tag map applied to every resource
  common_tags = {
    project     = var.project_name
    environment = var.environment
    region      = "ap-tokyo-1"
    managed-by  = "terraform"
  }

  # Derive a short name used in resource display names
  name_prefix = "${var.project_name}-${var.environment}-tky"
}

resource "oci_core_vcn" "main" {
  display_name  = "${local.name_prefix}-vcn"
  freeform_tags = local.common_tags
}
```

### Module

A module is a directory of `.tf` files that encapsulates a set of related resources.
Modules are the primary mechanism for code reuse in Terraform.

```
modules/networking/
├── main.tf       # All networking resources
├── variables.tf  # What the caller must/can provide
└── outputs.tf    # What the caller can read back
```

Calling a module:

```hcl
module "networking" {
  source = "../../modules/networking"   # path to the module directory

  # Pass values to the module's input variables
  compartment_id = var.compartment_id
  vcn_cidr       = "10.0.0.0/16"
  region_key     = "tky"
}

# Read a value from the module's outputs
resource "oci_core_instance" "vm" {
  subnet_id = module.networking.private_subnet_id
}
```

The same module can be called multiple times with different arguments — this is
exactly how this project deploys identical network stacks to Tokyo and Osaka.

---

## Terraform State

State is the mechanism Terraform uses to map your configuration to real-world resources.
It is stored as a JSON file (`terraform.tfstate`) and contains:

- The OCID of every resource Terraform created
- The last-known attribute values of each resource
- Dependency metadata

### Why state is necessary

When you run `terraform plan`, Terraform needs to know what already exists so it can
calculate the diff between current state and desired state. Without state, Terraform
would try to create everything from scratch on every run.

```
Your .tf files          terraform.tfstate        OCI (real world)
─────────────           ─────────────────        ────────────────
Desired state    ──►    Known state        ──►   Actual state
                        (what Terraform          (what exists)
                         last saw)
```

Terraform computes: `desired - known = plan`. Then it calls OCI APIs to make
`actual` match `desired`.

### Local vs Remote State

**Local state** (`terraform.tfstate` on your machine) is fine for solo learning but
has serious problems in a team:

- Two engineers running `terraform apply` simultaneously will corrupt the state file
- If your laptop is lost or the file is deleted, Terraform loses track of all resources
- The state file contains sensitive values (OCIDs, IPs) that should not sit on a laptop

**Remote state** stores the state file in a shared, durable location with locking.
In this project, OCI Object Storage is used as the backend. When one engineer runs
`terraform apply`, the state is locked so no one else can run apply simultaneously.

```hcl
# environments/tokyo/main.tf — remote backend configuration
terraform {
  backend "http" {
    address       = "https://objectstorage.ap-tokyo-1.oraclecloud.com/p/<PAR>/n/<NS>/b/<bucket>/o/tokyo/terraform.tfstate"
    update_method = "PUT"
  }
}
```

Each region uses a separate state key (`tokyo/terraform.tfstate`,
`osaka/terraform.tfstate`) so the two deployments are completely independent.

### State file security

The state file can contain sensitive data. Always:
- Add `terraform.tfstate` and `*.tfstate.*` to `.gitignore`
- Enable versioning on the state bucket (recover from accidental overwrites)
- Restrict bucket access to the team running Terraform

---

## The Terraform Workflow in Detail

```
Write .tf files
      │
      ▼
terraform init
  ├── Downloads provider plugins into .terraform/
  ├── Initializes the backend (local or remote state)
  └── Creates .terraform.lock.hcl (commit this file)
      │
      ▼
terraform validate
  └── Checks syntax and internal consistency (no API calls)
      │
      ▼
terraform plan
  ├── Reads current state
  ├── Calls OCI read APIs to refresh known state
  ├── Computes diff: desired vs known
  └── Prints the execution plan (no changes made yet)
      │
      ▼
Review plan output carefully
      │
      ▼
terraform apply
  ├── Shows the plan again and asks for confirmation
  ├── Calls OCI write APIs to create/update/delete resources
  ├── Updates state file after each resource operation
  └── Prints outputs
      │
      ▼
terraform destroy  (when you want to remove everything)
  ├── Computes a plan that deletes all resources in state
  └── Calls OCI delete APIs in reverse dependency order
```

### Reading plan output

The plan output uses symbols to indicate what will happen to each resource:

```
+ resource will be CREATED
~ resource will be UPDATED in-place (no downtime)
- resource will be DESTROYED
-/+ resource will be DESTROYED then re-CREATED (potential downtime!)
<= data source will be READ
```

The `-/+` (replace) symbol is the most important one to watch. Some attribute
changes cannot be applied in-place — OCI requires deleting and recreating the
resource. For production resources like VMs or VCNs, this means downtime.
Always read the plan carefully before applying.

Example plan output:

```
Terraform will perform the following actions:

  # module.networking.oci_core_vcn.main will be created
  + resource "oci_core_vcn" "main" {
      + cidr_blocks    = ["10.0.0.0/16"]
      + compartment_id = "ocid1.compartment..."
      + display_name   = "myproject-dev-tky-vcn"
      + id             = (known after apply)
    }

  # module.networking.oci_core_nat_gateway.main will be created
  + resource "oci_core_nat_gateway" "main" {
      ...
    }

Plan: 18 to add, 0 to change, 0 to destroy.
```

### Saving and using a plan file

For production deployments, it is best practice to save the plan to a file and
apply exactly that plan — preventing any drift between the review and the apply:

```bash
# Save the plan
terraform plan -out=tfplan

# Review the saved plan (human-readable)
terraform show tfplan

# Apply exactly the saved plan — no confirmation prompt, no surprises
terraform apply tfplan
```

---

## Dependency Graph

Terraform automatically builds a directed acyclic graph (DAG) of all resources
based on the references between them. Resources with no dependencies are created
in parallel; resources that depend on others wait for their dependencies to complete.

```hcl
resource "oci_core_vcn" "main" { ... }

resource "oci_core_nat_gateway" "main" {
  vcn_id = oci_core_vcn.main.id   # ← depends on VCN
}

resource "oci_core_subnet" "private" {
  vcn_id         = oci_core_vcn.main.id          # ← depends on VCN
  route_table_id = oci_core_route_table.private.id  # ← depends on route table
}
```

Terraform infers: VCN must be created first, then NAT Gateway and Route Table
(in parallel), then the private subnet.

You can visualize the graph:

```bash
terraform graph | dot -Tsvg > graph.svg
```

Sometimes you need to declare an explicit dependency that Terraform cannot infer
from references alone. Use `depends_on` for this:

```hcl
module "app_server" {
  source     = "../../modules/compute"
  depends_on = [module.networking]  # explicit: wait for all networking resources
}
```

---

## Useful Commands Reference

```bash
# Initialize — run once per environment, and after any provider/backend change
terraform init

# Format all .tf files recursively (run before every commit)
terraform fmt -recursive

# Check syntax without making API calls
terraform validate

# Show what will change
terraform plan

# Save plan to file (recommended for production)
terraform plan -out=tfplan

# Apply saved plan
terraform apply tfplan

# Apply with auto-approval (CI/CD only — never use interactively in production)
terraform apply -auto-approve

# Destroy all resources in state
terraform destroy

# Destroy a specific resource or module
terraform destroy -target=module.networking.oci_core_drg.main

# List all resources tracked in state
terraform state list

# Show details of a specific resource in state
terraform state show module.networking.oci_core_vcn.main

# Remove a resource from state without deleting it on OCI
terraform state rm module.networking.oci_core_vcn.main

# Import an existing OCI resource into state
terraform import module.networking.oci_core_vcn.main <vcn_ocid>

# Show all current output values
terraform output

# Show a specific output value (useful in scripts)
terraform output -raw drg_id

# Unlock a stuck state lock
terraform force-unlock <lock_id>
```

---

## Exercises

1. Open `modules/networking/main.tf`. Draw the dependency graph manually:
   which resources depend on which? Which can be created in parallel?

2. Run `terraform plan` in `environments/tokyo` (after filling in `terraform.tfvars`).
   Count how many resources will be created. Identify any `-/+` replacements.

3. Add a new output to `environments/tokyo/outputs.tf` that shows the
   `internet_gateway_id`. Run `terraform apply` and verify the output appears.

4. Change the `dns_search_domain` variable in `terraform.tfvars` and run
   `terraform plan`. What does the plan show? Is it an in-place update or a replace?

**Next:** [Guide 2 — OCI Concepts](./02-oci-concepts.md)
