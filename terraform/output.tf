output "ui_app_url" {
  description = "Default hostname for the UI App Service."
  value       = azurerm_app_service.ui_app.default_site_hostname
}

output "api_public_ip" {
  description = "Public IP address for the API VM."
  value       = azurerm_public_ip.api_public_ip.ip_address
}

output "mysql_fqdn" {
  description = "FQDN of the MySQL Flexible Server."
  value       = azurerm_mysql_flexible_server.mysql.fqdn
}