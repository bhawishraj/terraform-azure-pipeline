terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstateaccount"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Variable to store VM admin password from GitHub Secrets
variable "vm_admin_password" {
  type      = string
  sensitive = true
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

# 3. Network Interfaces (NICs) for 3 VMs
resource "azurerm_network_interface" "example_nic" {
  count               = 3
  name                = "example-nic-${count.index + 1}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 4. Windows Virtual Machines (3 instances)
resource "azurerm_windows_virtual_machine" "example_vm" {
  count               = 3
  name                = "example-windows-vm-${count.index + 1}"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  size                = "Standard_B1ms" # ~2 GB RAM, closest to 1 GB
  admin_username      = "azureuser"
  admin_password      = var.vm_admin_password
  network_interface_ids = [
    azurerm_network_interface.example_nic[count.index].id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 25
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
  name                     = "examplestoracct"
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

# 6. Azure SQL Server + Database
resource "azurerm_sql_server" "example_sql_server" {
  name                         = "examplesqlserver01"
  resource_group_name          = azurerm_resource_group.example.name
  location                     = azurerm_resource_group.example.location
  version                      = "12.0"
  administrator_login          = "sqladminuser"
  administrator_login_password = "YourSecurePassword123!"
}

resource "azurerm_sql_database" "example_sql_db" {
  name                = "example-sqldb"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  server_name         = azurerm_sql_server.example_sql_server.name
  sku_name            = "S0"
}

# 7. Azure Cosmos DB + SQL Database
resource "azurerm_cosmosdb_account" "example_cosmos" {
  name                = "examplecosmosacct01"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }

  geo_location {
    location          = azurerm_resource_group.example.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "example_cosmos_db" {
  name                = "example-cosmosdb"
  resource_group_name = azurerm_resource_group.example.name
  account_name        = azurerm_cosmosdb_account.example_cosmos.name
}
