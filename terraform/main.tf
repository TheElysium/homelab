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

  datastore_images = "local"     # cloud image + cloud-init snippets
  datastore_disks  = "local-lvm" # VM disks (LVM-thin)

  image_url  = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  cloud_user = "debian"

  lan_bridge  = "vmbr0"
  lan_gateway = "192.168.1.1"

  internal_bridge = "vmbr1"

  ssh_public_key_path = pathexpand("~/.ssh/homelab.pub")

  vms = {
    "k8s-master" = {
      role          = "control_plane"
      vm_id         = 200
      cpu_cores     = 2 # kubeadm minimum
      memory_mb     = 3072
      memory_min    = 2048
      disk_gb       = 20
      data_disk_gb  = 0
      lan_cidr      = "192.168.1.200/24"
      internal_cidr = "10.0.10.11/24"
    }
    "k8s-worker-1" = {
      role          = "worker"
      vm_id         = 201
      cpu_cores     = 2
      memory_mb     = 3584
      memory_min    = 2560
      disk_gb       = 32
      data_disk_gb  = 0
      lan_cidr      = "192.168.1.201/24"
      internal_cidr = "10.0.10.12/24"
    }

    "k8s-worker-2" = {
      role          = "worker"
      vm_id         = 202
      cpu_cores     = 2
      memory_mb     = 3584
      memory_min    = 2560
      disk_gb       = 32
      data_disk_gb  = 0
      lan_cidr      = "192.168.1.202/24"
      internal_cidr = "10.0.10.13/24"
    }
    "nfs-server" = {
      role          = "storage"
      vm_id         = 203
      cpu_cores     = 2
      memory_mb     = 1024
      memory_min    = 512
      disk_gb       = 10
      data_disk_gb  = 40
      lan_cidr      = "192.168.1.203/24"
      internal_cidr = "10.0.10.10/24"
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
  for_each = local.vms

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

resource "proxmox_virtual_environment_vm" "debian_vms" {
  for_each = local.vms

  vm_id     = each.value.vm_id
  name      = each.key
  node_name = local.node_name

  stop_on_destroy = true
  protection      = each.value.role == "storage"

  tags = [each.value.role]

  operating_system {
    type = "l26"
  }
  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = each.value.memory_min
  }

  disk {
    datastore_id = local.datastore_disks
    import_from  = proxmox_download_file.debian-13-genericcloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_gb
  }

  dynamic "disk" {
    for_each = each.value.data_disk_gb > 0 ? [each.value.data_disk_gb] : []

    content {
      datastore_id = local.datastore_disks
      interface    = "virtio1"
      file_format  = "raw"
      iothread     = true
      discard      = "on"
      size         = disk.value
    }
  }

  initialization {
    datastore_id = local.datastore_disks
    ip_config {
      ipv4 {
        address = each.value.lan_cidr
        gateway = local.lan_gateway
      }
    }
    ip_config {
      ipv4 {
        address = each.value.internal_cidr
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config[each.key].id
  }

  network_device {
    bridge = local.lan_bridge
  }
  network_device {
    bridge = local.internal_bridge
  }
}