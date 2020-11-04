$node

$features='Hyper-V', 'failover-clustering', 'File-Services', 'Data-Center-Bridging'

#install windows Features
Invoke-Command -ComputerName $node -ScriptBlock {Install-WindowsFeature $features -IncludeAllSubFeature -IncludeManagementTools -Restart}



# Create SET-enabled vSwitch for Hyper-V using 1GbE ports
New-VMSwitch -Name "S2DSwitch" -NetAdapterName "1GbE-Port1", "1GbE-Port2" -EnableEmbeddedTeaming $true `
-AllowManagementOS $false

# Add host vNIC to the vSwitch just created
Add-VMNetworkAdapter -SwitchName "S2DSwitch" -Name "vNIC-Host" -ManagementOS

# Enable RDMA on 10GbE ports
Enable-NetAdapterRDMA -Name "10GbE-Port1"
Enable-NetAdapterRDMA -Name "10GbE-Port2"

# Configure IP and subnet mask, no default gateway for Storage interfaces
New-NetIPAddress -InterfaceAlias "10GbE-Port1" -IPAddress 10.10.11.11 -PrefixLength 24
New-NetIPAddress -InterfaceAlias "10GbE-Port2" -IPAddress 10.10.12.11 -PrefixLength 24
New-NetIPAddress -InterfaceAlias "vEthernet (vNIC-Host)" -IPAddress 222.222.61.161 -PrefixLength 24 `
-DefaultGateway 222.222.61.5

# Configure DNS on each interface, but do not register Storage interfaces
Set-DnsClient -InterfaceAlias "10GbE-Port1" -RegisterThisConnectionsAddress $false
Set-DnsClientServerAddress -InterfaceAlias "10GbE-Port1" -ServerAddresses 222.222.61.5
Set-DnsClient -InterfaceAlias "10GbE-Port2" -RegisterThisConnectionsAddress $false
Set-DnsClientServerAddress -InterfaceAlias "10GbE-Port2" -ServerAddresses 222.222.61.5
Set-DnsClientServerAddress -InterfaceAlias "vEthernet (vNIC-Host)" -ServerAddresses 222.222.61.5




#Node 1

# Configure IP and subnet mask, no default gateway for Storage interfaces
New-NetIPAddress -InterfaceAlias "LOM1-Port1" -IPAddress 10.10.11.11 -PrefixLength 24
New-NetIPAddress -InterfaceAlias "LOM1-Port2" -IPAddress 10.10.12.11 -PrefixLength 24
New-NetIPAddress -InterfaceAlias "vEthernet (vNIC-Host)" -IPAddress 192.168.5.31 -PrefixLength 24 `
-DefaultGateway 192.168.5.1
# Configure DNS on each interface, but do not register Storage interfaces
Set-DnsClient -InterfaceAlias "LOM1-Port1" -RegisterThisConnectionsAddress $false
Set-DnsClientServerAddress -InterfaceAlias "LOM1-Port1" -ServerAddresses 192.168.5.10
Set-DnsClient -InterfaceAlias "LOM1-Port2" -RegisterThisConnectionsAddress $false

Set-DnsClientServerAddress -InterfaceAlias "LOM1-Port2" -ServerAddresses 192.168.5.10
Set-DnsClientServerAddress -InterfaceAlias "vEthernet (vNIC-Host)" -ServerAddresses 192.168.5.10

#Create Cluster
Test-Cluster -Node S2D-Node01, S2D-Node02 -Include Inventory, Network, "Storage Spaces Direct", `
"System Configuration"
New-Cluster -Name S2D-Cluster -Node S2D-Node01, S2D-Node02 -StaticAddress 222.222.61.160 -NoStorage

#Change Cluster Network Names
# Update the cluster network names that were created by default
# First, look at what's there
Get-ClusterNetwork | Format-Table Name, Role, Address
# Change the cluster network names so they are consistent with the individual nodes
(Get-ClusterNetwork -Name "Cluster Network 1").Name = "Storage1"
(Get-ClusterNetwork -Name "Cluster Network 2").Name = "Storage2"
(Get-ClusterNetwork -Name "Cluster Network 3").Name = "Host"
# Check to make sure the cluster network names were changed correctly
Get-ClusterNetwork | format-table Name, Role, Address


Enable-ClusterStorageSpacesDirect -PoolFriendlyName S2DPool

#Create Volumes
# For nested two-way mirroring
New-StorageTier -FriendlyName NestedMirror -StoragePoolFriendlyName S2D* -ResiliencySettingName Mirror `
-MediaType SSD -NumberOfDataCopies 4
# For nested mirror-accelerated parity
New-StorageTier -FriendlyName NestedParity -StoragePoolFriendlyName S2D* -ResiliencySettingName Parity `
-MediaType SSD -NumberOfDataCopies 2 -PhysicalDiskRedundancy 1 -NumberOfGroups 1 `
-FaultDomainAwareness StorageScaleUnit -ColumnIsolation PhysicalDisk

