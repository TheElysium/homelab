terraform {
  # Floor set to the version this configuration was written and tested with.
  # No upper bound: Terraform keeps backward compatibility across 1.x minors.
  required_version = ">= 1.15"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Exact pin: this provider is pre-1.0, minor releases carry breaking
      # schema changes (the ongoing virtual_environment_ prefix removal).
      version = "0.111.1"
    }
  }
}
