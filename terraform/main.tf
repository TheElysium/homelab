provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
  
  ssh {
    username    = "terraform"
    private_key = file(pathexpand("~/.ssh/pve-terraform"))
  }
}

data "proxmox_version" "homelab" {}

output "data_proxmox_version" {
  value = {
    release       = data.proxmox_version.homelab.release
    repository_id = data.proxmox_version.homelab.repository_id
    version       = data.proxmox_version.homelab.version
  }
}

locals {
  node_name = "pve"

  datastore_images = "local"     # image cloud + snippets cloud-init
  datastore_disks  = "local-lvm" # VM disks (LVM-thin)

  image_url  = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  cloud_user = "debian"

  lan_bridge  = "vmbr0"
  lan_gateway = "192.168.1.1"

  internal_bridge = "vmbr1"

  ssh_public_key_path = pathexpand("~/.ssh/homelab.pub")

  nodes = {
    "k8s-master" = {
      vm_id         = 200
      cpu_cores     = 2 # kubeadm minimum
      memory_mb     = 3072
      memory_min    = 2048
      disk_gb       = 20
      lan_cidr      = "192.168.1.200/24"
      internal_cidr = "10.0.10.11/24"
    }
  }
}

resource "proxmox_download_file" "debian-13-genericcloud_image" {
  content_type = "import"
  datastore_id = local.datastore_images
  node_name    = local.node_name
  url          = local.image_url
  file_name    = "debian-13-genericcloud-amd64.qcow2"
  overwrite    = true
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = local.nodes

  content_type = "snippets"
  datastore_id = local.datastore_images
  node_name    = local.node_name

  source_raw {
    file_name = "${each.key}.cloud-config.yaml"

    data = <<-EOT
      #cloud-config
      hostname: ${each.key}

      users:
        - name: ${local.cloud_user}
          groups: [sudo]
          shell: /bin/bash
          sudo: "ALL=(ALL) NOPASSWD:ALL"
          ssh_authorized_keys:
            - ${trimspace(file(local.ssh_public_key_path))}

      package_update: true
      packages:
        - qemu-guest-agent

      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOT
  }
}

# resource "proxmox_virtual_environment_vm" "k8s-master" {
#   initialization {
#     ip_config {
#       ipv4 {
#         address = local.nodes.k8s-master.lan_cidr
#         gateway = local.lan_gateway
#       }
#     }

#     user_account {
#       username = "debian"
#       keys     = [trimspace(file(local.ssh_public_key_path))]
#     }
#   }
# }