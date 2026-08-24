# OCI Network Infrastructure — Tokyo & Osaka

IaC project to deploy the full network stack on Oracle Cloud Infrastructure
across two Japan regions: **Tokyo (ap-tokyo-1)** and **Osaka (ap-osaka-1)**.

**Deadline:** 2025-05-16

## Scope

| Resource | Tokyo | Osaka |
|---|---|---|
| VCN | `10.0.0.0/16` | `10.1.0.0/16` |
| Public Subnet | `10.0.1.0/24` | `10.1.1.0/24` |
| Private Subnet | `10.0.2.0/24` | `10.1.2.0/24` |
| Internet Gateway | ✅ | ✅ |
| NAT Gateway | ✅ | ✅ |
| Service Gateway | ✅ | ✅ |
| DRG + VCN Attachment | ✅ | ✅ |
| DHCP Options | ✅ | ✅ |
| Security List (Windows) | ✅ | ✅ |
| NSG: bastion-nsg | ✅ | ✅ |
| NSG: app-nsg | ✅ | ✅ |
| OS | Windows Server | Windows Server |

## Requirements

| Tool | Minimum version |
|---|---|
| Terraform | >= 1.5.0 |
| OCI Terraform Provider | ~> 8.12.0 |

## Project Structure

```
oci-terraform-infra/
├── docs/
│   ├── 01-terraform-basics.md
│   ├── 02-oci-concepts.md
│   ├── 03-project-walkthrough.md
│   └── 04-operations-guide.md
├── modules/
│   ├── networking/          # Reusable network module (VCN, subnets, gateways, NSG, SL)
│   ├── compute/             # Windows VM module
│   └── storage/             # Block volume + Object Storage module
├── environments/
│   ├── tokyo/               # ap-tokyo-1  VCN: 10.0.0.0/16
│   └── osaka/               # ap-osaka-1  VCN: 10.1.0.0/16
└── .gitignore
```

## Quick Start

### 1. Prepare OCI credentials

```bash
# Create OCI API key
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 4096
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

Upload `oci_api_key_public.pem` to:
**OCI Console → Profile → User Settings → API Keys → Add API Key**

Copy the displayed fingerprint.

### 2. Deploy Tokyo

```bash
cd environments/tokyo
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials and management_cidr

terraform init
terraform plan
terraform apply
```

### 3. Deploy Osaka

```bash
cd environments/osaka
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (same credentials, same compartment)

terraform init
terraform plan
terraform apply
```

### 4. Connect Tokyo ↔ Osaka via DRG Remote Peering

After both regions are deployed, retrieve the DRG IDs:

```bash
# Tokyo DRG
cd environments/tokyo && terraform output drg_id

# Osaka DRG
cd environments/osaka && terraform output drg_id
```

Then create a Remote Peering Connection (RPC) in the OCI Console:
**Networking → Dynamic Routing Gateways → Tokyo DRG → Remote Peering Connections → Create**
Set the peer DRG OCID to the Osaka DRG ID.

## Network Architecture

```
                    Internet
                       │
          ┌────────────┴────────────┐
          │                         │
   ┌──────▼──────┐           ┌──────▼──────┐
   │  Tokyo IGW  │           │  Osaka IGW  │
   └──────┬──────┘           └──────┬──────┘
          │                         │
   ┌──────▼──────────────┐   ┌──────▼──────────────┐
   │  Tokyo VCN          │   │  Osaka VCN          │
   │  10.0.0.0/16        │   │  10.1.0.0/16        │
   │                     │   │                     │
   │  Public  10.0.1.0/24│   │  Public  10.1.1.0/24│
   │  [Bastion Windows]  │   │  [Bastion Windows]  │
   │                     │   │                     │
   │  Private 10.0.2.0/24│   │  Private 10.1.2.0/24│
   │  [App Windows VMs]  │   │  [App Windows VMs]  │
   │                     │   │                     │
   │  NAT GW → Internet  │   │  NAT GW → Internet  │
   │  SGW → OCI Services │   │  SGW → OCI Services │
   │  DRG ───────────────┼───┼──── DRG             │
   └─────────────────────┘   └─────────────────────┘
              Tokyo ↔ Osaka via DRG Remote Peering
```

## Documentation

See the [`docs/`](./docs/) folder for step-by-step learning guides.
