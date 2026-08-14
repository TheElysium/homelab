variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox server endpoint"
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox API Token"
  sensitive   = true
}