PowerShell

###
#This script will change the subnet of a specified virtual machine and allocate a static IP
###

##############################################################
#define Variables
$RGname = 'SiteCore' #VM and NIC RG
$VMName = 'PRD-AZ-DB-01' #VM Name
$VNetName = 'SitecoreVNET' #Virt Net name
$TarSubnetName = 'LAN' #Target subnet name

#Target subnet range is 10.87.1.64/27
$StaticIP = '10.87.1.70'


##############################################################

#region Get Azure Subscriptions
Login-AzureRmAccount
$subscriptions = Get-AzureRmSubscription
$menu = @{}
for ($i = 1;$i -le $subscriptions.count; $i++) 
{
  Write-Host -Object "$i. $($subscriptions[$i-1].SubscriptionName)"
  $menu.Add($i,($subscriptions[$i-1].SubscriptionId))
}
[int]$ans = Read-Host -Prompt 'Enter selection'
$subscriptionID = $menu.Item($ans)
$subscription = Get-AzureRmSubscription -SubscriptionId $subscriptionID
Set-AzureRmContext -SubscriptionName $subscription.SubscriptionName
#endregion



#retrieve VM and network
$VM = Get-AzureRmVM -Name $VMName -ResourceGroupName $RGname
$NIC = get-azurermnetworkinterface -ResourceGroupName $RGname | where -Property Id -EQ $VM.NetworkInterfaceIDs

$VNET = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $RGname
$TarSubnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VNET -Name $TarSubnetName

#set new subnet
$NIC.IpConfigurations[0].Subnet.Id = $TarSubnet.Id

#Once the subnet has been set and applied we can apply the static IP address
$NIC.IpConfigurations[0].PrivateIpAddress = $StaticIP
$NIC.IpConfigurations[0].PrivateIPAllocationMethod = 'Static'
Set-AzureRmNetworkInterface -NetworkInterface $NIC

#output
$prv =  $NIC.IpConfigurations | select-object -ExpandProperty PrivateIpAddress
$alloc =  $NIC.IpConfigurations | select-object -ExpandProperty PrivateIpAllocationMethod
Write-Output "$($vm.Name) : $prv , $alloc"
