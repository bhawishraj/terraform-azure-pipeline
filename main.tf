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

variable "vm_admin_password" {
  type      = string
  sensitive = true
}

# Random suffix for unique resource names
resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

# 1. Resource Group
resource "azurerm_resource_group" "example" {
  name     = "rg-example"
  location = "East US"
}

# 2. Virtual Network & Subnet
resource "azurerm_virtual_network" "example_vnet" {
  name                = "example-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example_subnet" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# 3. Create 3 NICs for 3 Windows VMs
resource "azurerm_network_interface" "example_nic" {
  count               = 3
  name                = "nic-${count.index + 1}-${random_integer.suffix.result}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 4. Create 3 Windows Virtual Machines
resource "azurerm_windows_virtual_machine" "example_vm" {
  count               = 3
  name                = "winvm-${count.index + 1}-${random_integer.suffix.result}"
  computer_name       = "WIN${count.index + 1}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  size                = "Standard_B1ms"
  admin_username      = "azureuser"
  admin_password      = var.vm_admin_password
  network_interface_ids = [
    azurerm_network_interface.example_nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    # Removed disk_size_gb to allow default image size (127 GB for Windows Server 2019)
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}
# 5. Azure Storage Account + Private Blob Container
resource "azurerm_storage_account" "example_storage" {
  name                     = "stor${random_integer.suffix.result}"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "example_container" {
  name                  = "app-data"
  storage_account_name  = azurerm_storage_account.example_storage.name
  container_access_type = "private"
}

# 6. Azure SQL Server (MSSQL) + Database
resource "azurerm_mssql_server" "example_sql_server" {
  name                         = "sqlsrv${random_integer.suffix.result}"
  resource_group_name          = azurerm_resource_group.example.name
  location                     = "East US 2" # Different region due to quota issues in East US
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = "YourSecurePassword123!"
}

resource "azurerm_mssql_database" "example_sql_db" {
  name      = "sqldb${random_integer.suffix.result}"
  server_id = azurerm_mssql_server.example_sql_server.id
  sku_name  = "S0"
}

# 7. Azure Cosmos DB + SQL Database
resource "azurerm_cosmosdb_account" "example_cosmos" {
  name                = "cosmosacct${random_integer.suffix.result}"
  location            = "East US 2" # Changed from East US
  resource_group_name = azurerm_resource_group.example.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = "East US 2"
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "example_cosmos_db" {
  name                = "cosmosdb${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example_cosmos.name
}

