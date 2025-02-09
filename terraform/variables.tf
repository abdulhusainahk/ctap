variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-multi-tier-demo"
}

variable "location" {
  description = "Azure region for deployment."
  type        = string
  default     = "eastus"
}

variable "subscription_id" {
  description = "Azure subscription ID (optional if provided via environment variable)."
  type        = string
  default     = ""
}