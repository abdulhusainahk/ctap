resource "random_pet" "suffix" {
  length = 2
}
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "ctap-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "ui" {
  name                 = "ctap-ui-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "api" {
  name                 = "ctap-api-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "ctap-db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
  delegation {
  name = "mysql_delegation"
  service_delegation {
    name = "Microsoft.DBforMySQL/flexibleServers"
    actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  }
}
}

resource "azurerm_app_service_plan" "ui_plan" {
  name                = "ctap-ui-appserviceplan-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "ui_app" {
  name                = "ctap-ui-webapp-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.ui_plan.id

  site_config {
    linux_fx_version = "NODE|14-lts"
    app_command_line = "npx serve -s ."
  }

  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }
  depends_on = [ azurerm_linux_virtual_machine.vm_api ]
}


data "archive_file" "ui_zip" {
  type        = "zip"
  source_dir  = "static"                 
  output_path = "${path.module}/ui.zip" 
}

resource "null_resource" "deploy_ui" {
  triggers = {
    ui_zip_hash = data.archive_file.ui_zip.output_base64sha256
  }
  provisioner "local-exec" {
    command = "az webapp deploy --resource-group ${var.resource_group_name} --name ${azurerm_app_service.ui_app.name} --src-path ./ui.zip"
  }
  depends_on = [ azurerm_app_service.ui_app ]
}


resource "azurerm_public_ip" "api_public_ip" {
  name                = "ctap-api-public-ip-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_network_security_group" "nsg_api_ssh" {
  name                = "nsg-api-ssh-${random_pet.suffix.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "152.58.22.19/32"
    destination_address_prefix = "0.0.0.0/0"
    destination_port_range     = "22"
    source_port_range          = "*"
  }
  security_rule {
    name                       = "Allow-8080"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_port_range     = "8080"
    source_port_range          = "*"
  }
}

resource "azurerm_network_interface" "nic_api" {
  name                = "ctap-nic-api"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.api.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.api_public_ip.id
  }
}
resource "azurerm_network_interface_security_group_association" "nsg_integrate" {
  network_interface_id      = azurerm_network_interface.nic_api.id
  network_security_group_id = azurerm_network_security_group.nsg_api_ssh.id
  depends_on = [ azurerm_network_security_group.nsg_api_ssh ,azurerm_network_interface.nic_api]
}
resource "azurerm_linux_virtual_machine" "vm_api" {
  name                  = "ctap-vm-api"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B1s"
  admin_username        = "azureuser"
  admin_password        = "P@ssw0rd1234!"  # Secure this properly in production
  network_interface_ids = [azurerm_network_interface.nic_api.id]
  disable_password_authentication= false
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  # Bootstrap script to install Node.js
  custom_data = base64encode(<<EOF
#!/bin/bash
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get update
sudo apt-get install -y nodejs
EOF
  )

  # Copy the local app.js file to the VM
  provisioner "file" {
    source      = "app.js"
    destination = "/home/azureuser/app.js"
  }

connection {
  type     = "ssh"
  host     = azurerm_public_ip.api_public_ip.ip_address
  user     = "azureuser"
  password = "P@ssw0rd1234!"
  timeout  = "15m"
}

provisioner "file" {
  source      = "app.js"
  destination = "/home/azureuser/app.js"
}

provisioner "remote-exec" {
  inline = [
    "openssl req -nodes -new -x509 -keyout server.key -out server.cert -days 365 -subj '/C=US/ST=California/L=SanFrancisco/O=MyOrganization/OU=IT/CN=your.domain.com'",
    "chmod +x /home/azureuser/app.js",
    "curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -",
    "sudo apt-get install -y nodejs",
    "npm install express",
    "npm install cors",
    "npm install https",
    "npm install fs",
    "npm install express-session",
    "npm install mysql2",
    "nohup node /home/azureuser/app.js > api.log 2>&1 &"
  ]
}
depends_on = [ azurerm_network_interface_security_group_association.nsg_integrate ]

}
resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = "mysqlserverctap"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  administrator_login    = "mysqladmin"
  administrator_password = "P@ssw0rd1234!"  # Secure in production
  version                = "8.0.21"
  sku_name               = "B_Standard_B1ms"  # Valid SKU (check with Azure CLI for eastus)
  backup_retention_days  = 7
  geo_redundant_backup_enabled = false
  delegated_subnet_id = azurerm_subnet.db.id
  lifecycle {
    ignore_changes = [zone]
  }
  depends_on = [ azurerm_subnet.db ]
}
