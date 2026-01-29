terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatestorage9"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# ------------ Variables ------------
variable "vm_admin_password" {
  type      = string
  sensitive = true
}

# Random suffix for non-core names
resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

# ------------ Core Layer (Stable Names & Location) ------------

# Resource Group (do not change name or location after creation)
resource "azurerm_resource_group" "core_rg" {
  name     = "rg-example"
  location = "southeastasia"
}

# Virtual Network (stable name)
resource "azurerm_virtual_network" "core_vnet" {
  name                = "vnet-core"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.core_rg.location
  resource_group_name = azurerm_resource_group.core_rg.name
}

# Subnet (stable name)
resource "azurerm_subnet" "core_subnet" {
  name                 = "subnet-core"
  resource_group_name  = azurerm_resource_group.core_rg.name
  virtual_network_name = azurerm_virtual_network.core_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# ------------ Compute Layer (Flexible) ------------

# Network Interfaces (okay to recreate independently)
resource "azurerm_network_interface" "vm_nic" {
  count               = 3
  name                = "nic-${count.index + 1}-${random_integer.suffix.result}"
  location            = azurerm_resource_group.core_rg.location
  resource_group_name = azurerm_resource_group.core_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.core_subnet.id
    private_ip_address_allocation = "Dynamic"
  }

  depends_on = [azurerm_subnet.core_subnet]
}

# Windows Virtual Machines
resource "azurerm_windows_virtual_machine" "vm" {
  count               = 3
  name                = "vm-${count.index + 1}-${random_integer.suffix.result}"
  computer_name       = "WIN${count.index + 1}"
  resource_group_name = azurerm_resource_group.core_rg.name
  location            = azurerm_resource_group.core_rg.location
  size                = "Standard_B1ms"
  admin_username      = "azureuser"
  admin_password      = var.vm_admin_password
  network_interface_ids = [
    azurerm_network_interface.vm_nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    # Removed disk_size_gb to use default (127 GB for Windows Server 2019)
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

# ------------ Service Layer (Stable) ------------

# Storage Account (stable name, unique in Azure)
resource "azurerm_storage_account" "app_storage" {
  name                     = "stor${random_integer.suffix.result}"
  resource_group_name      = azurerm_resource_group.core_rg.name
  location                 = azurerm_resource_group.core_rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "app_container" {
  name                  = "app-data"
  storage_account_name  = azurerm_storage_account.app_storage.name
  container_access_type = "private"
}

# SQL Server (stable name)
resource "azurerm_mssql_server" "app_sql_server" {
  name                         = "sqlserver-core"
  resource_group_name          = azurerm_resource_group.core_rg.name
  location                     = azurerm_resource_group.core_rg.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = "YourSecurePassword123!"
}

# SQL Database
resource "azurerm_mssql_database" "app_sql_db" {
  name      = "sqldb${random_integer.suffix.result}"
  server_id = azurerm_mssql_server.app_sql_server.id
  sku_name  = "S0"
}

# Cosmos DB Account
resource "azurerm_cosmosdb_account" "app_cosmos" {
  name                = "cosmosacct${random_integer.suffix.result}"
  location            = azurerm_resource_group.core_rg.location
  resource_group_name = azurerm_resource_group.core_rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = azurerm_resource_group.core_rg.location
    failover_priority = 0
  }
}

# Cosmos DB SQL Database
resource "azurerm_cosmosdb_sql_database" "app_cosmos_sql_db" {
  name                = "cosmosdb${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.core_rg.name
  account_name        = azurerm_cosmosdb_account.app_cosmos.name
}
