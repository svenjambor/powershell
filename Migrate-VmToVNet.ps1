# Needed Parameters for the script
Param
(
    [Parameter(Mandatory=$True, HelpMessage="Enter the Resource Group of the original VM")]
    [string] $OriginalResourceGroup,
    [Parameter(Mandatory=$True, HelpMessage="Enter the original VM name")]
    [string] $OriginalvmName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the new VM name")]
    [string] $NewvmName,
    [Parameter(Mandatory=$false, HelpMessage="Enter the new resource group name")]
    [string] $NewRGName,
    [Parameter(Mandatory=$false, HelpMessage="Enter the new availability set name")]
    [string] $NewAvailSetName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the target VNet resource group")]
    [string] $NewVnetResourceGroup,
    [Parameter(Mandatory=$True, HelpMessage="Enter the target VNet name")]
    [string] $NewVNetName,
    [Parameter(Mandatory=$True, HelpMessage="Enter the target Subnet name")]
    [string] $NewSubnet,
    [Parameter(Mandatory=$True, HelpMessage="Enter Azure region")]
    [string] $Location,
    [Parameter(Mandatory=$False, HelpMessage="Enter Linux if moving a Linux VM")]
    [ValidateSet('Windows','Linux')]
    [string] $OSType
)


################
# SCRIPT HEADER
################

<#
    .SYNOPSIS
        Migrates an Azure VM from current VNet to a new VNet in Azure by creating a new VM in new VNet retaining the original VMs configuration and data disks.

    .DESCRIPTION
        Steps in move VM to new VNet: 
            (1) Gathers info on existing VM, VNet, and subnet.
            (2) Removes the original VM while saving all data disks and VM info.
            (3) Creates VM configuration for new VM, creates nic for new VM, and new availability set.  
            (4) Adds data disks to new VM, adds nics to new VM, adds VM to the new VNet.
            (5) Creates new VM and adds the VM to the new VNet.
        
        ***NOTE***
        The line starting with Set-AzVMOSDisk be sure to set -Linux or -Windows depending on VM OS of the original VM at the end of the line before running this script.
    
    .PARAMETER OriginalResourceGroup
        Resource Group of the original VM
    .PARAMETER OriginalvmName
        Original VM name
    .PARAMETER NewvmName
        New VM name
    .PARAMETER NewRGName
        Resource Group set name
    .PARAMETER NewAvailSetName
        New availability set name
    .PARAMETER NewVnetResourceGroup
        New VNet resource group
    .PARAMETER NewVNetName
        New VNet name
    .PARAMETER NewSubnet
        New Subnet name
    .PARAMETER Location
        Azure region
    .PARAMETER Location
        Azure region

    .EXAMPLE
      OriginalResourceGroup : RG_STIZONACG
      OriginalvmName : STIZONACG
      NewvmName : INSZOACG
      NewRGName : RG_INSZOACG
      NewAvailSetName : AVSet_INSZOACG
      NewVnetResourceGroup : RG_Vnet_INSZO-Production-ExternalVMs
      NewVNetName : VNet_INSZO-Production-ExternalVMs
      NewSubnet : ACG
      Location : $Location

      if left blank, NewRGName and NewAvailSetName will be built automagically below with presets RG_ and AVSet_

    
    .NOTES
        Original Name: Vnet-to-Vnet VM migration.ps1  
        Org. Author:   Microsoft MVP - Steve Buchanan (www.buchatech.com)
        Version:       1.0
        Creation Date: 8-22-2019
        Edits:         removed PS5, added subscription change possibility

    .PREREQUISITES
        PowerShell version: 7
        Modules:  AZ module.

    .CAVEATS
        Make sure you disable the VM's backup and delete any backup data in site recovery if disks are moved around, otherwise moving the disks will fail
#>


##############

Write-Host "Log into Azure Services..."
#Azure Account Login
try {
                Connect-AzAccount -ErrorAction Stop
}
catch {
                # The exception lands in [Microsoft.Azure.Commands.Common.Authentication.AadAuthenticationCanceledException]
                Write-Host "User Cancelled The Authentication" -ForegroundColor Yellow
                exit
}


# Set Source and Target Azure Subscription ID Variables

$originalSubscriptionID = Get-AzSubscription | Out-GridView -PassThru -Title "Select the SOURCE Azure subscription you want to use."
$targetSubscriptionID = Get-AzSubscription | Out-GridView -PassThru -Title "Select the TARGET Azure subscription you want to use."

### Start with source subscription, change later if needed
Select-AzSubscription -Subscription $originalSubscriptionID.name


########################
# GET VM & Network INFO
########################
    
#Get the details of the VM to be moved
    $originalVM = Get-AzVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName

###################
# REMOVE ORIGNAL VM
###################

#Remove the original VM
    Remove-AzVM -ResourceGroupName $OriginalResourceGroup -Name $OriginalvmName    

#################################
# CREATE NEW VM CONFIG, NIC, AS
#################################


# Set Azure subscription to target subscription
Select-AzSubscription -Subscription $targetSubscriptionID.name

# Check if ResourceGroup exists and create it if needed (first: check if the name was actually set, otherwise build it from the new VM's name)

if(($NewRGName -eq "") -or ($NewRGName -eq $null)){$NewRGName = "RG_" + $NewvmName}

if($(Get-AzResourceGroup -Name $NewRGName -ErrorAction SilentlyContinue) -eq $null){
    New-AzResourceGroup -Name $NewRGName -Location $Location
}

# move disks to the target resource group (and possibly subscription) if needed

if(($targetSubscriptionID -ne $originalSubscriptionID) -or($NewRGName -ne $OriginalResourceGroup)){

    #making sure we're back in the source subscription
    Select-AzSubscription -Subscription $originalSubscriptionID.name

    #Move OS Disk
    Move-AzResource -ResourceId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -DestinationResourceGroupName $NewRGName -DestinationSubscriptionId $targetSubscriptionID.Id -Force
    $originalVM.StorageProfile.OsDisk.ManagedDisk.Id = $originalVM.StorageProfile.OsDisk.ManagedDisk.Id.Replace($originalSubscriptionID.Id,$targetSubscriptionID.Id).Replace($OriginalResourceGroup,$NewRGName)

    #Move any Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
        "old id: $($disk.ManagedDisk.Id)"
        Move-AzResource -ResourceId $disk.ManagedDisk.Id  -DestinationResourceGroupName $NewRGName -DestinationSubscriptionId $targetSubscriptionID.Id -Force
        $disk.ManagedDisk.Id = $disk.ManagedDisk.Id.Replace($originalSubscriptionID.Id,$targetSubscriptionID.Id).Replace($OriginalResourceGroup,$NewRGName)
        "new id: $($disk.ManagedDisk.Id)"
    }
}

# Set Azure subscription back to target subscription
Select-AzSubscription -Subscription $targetSubscriptionID.name

#Get info for the VNet and subnet
    $NewVnet = Get-AzVirtualNetwork -Name $NewVNetName -ResourceGroupName $NewVnetResourceGroup
    $backEndSubnet = $NewVnet.Subnets|?{$_.Name -eq $NewSubnet}

#Create new availability set if it does not exist (first: check if the name was actually set, otherwise build it from the new VM's name)

    if(($NewAvailSetName -eq "") -or ($NewAvailSetName -eq $null)){$NewAvailSetName = "AVSet_$($($NewvmName).replace('vm',''))"}
    $availSet = Get-AzAvailabilitySet -ResourceGroupName $NewRGName -Name $NewAvailSetName -ErrorAction Ignore
    if (-Not $availSet) {$availSet = New-AzAvailabilitySet -Location "$Location" -Name $NewAvailSetName -ResourceGroupName $NewRGName -PlatformFaultDomainCount 2 -PlatformUpdateDomainCount 2 -Sku Aligned}

#Create the basic configuration for the new VM
    $newVM = New-AzVMConfig -VMName $NewvmName -VMSize $originalVM.HardwareProfile.VmSize -AvailabilitySetId $availSet.Id
        
#***NOTE*** Use -Linux or -Windows at the end of this line based on OSType (if nothing is set, default to Windows)
if($OSType -eq "Linux"){
 Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $originalVM.StorageProfile.OsDisk.Name -Linux
 }
else{
 Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $originalVM.StorageProfile.OsDisk.Name -Windows
 }

#Create new NIC for new VM
    $NewNic = New-AzNetworkInterface -ResourceGroupName $NewRGName `
      -Name "$($NewvmName)_NIC0" `
      -Location "$Location" `
      -SubnetId $backEndSubnet.Id

#########################
# ADD DATA DISKS AND NICS
#########################

#Add Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { Add-AzVMDataDisk -VM $newVM -Name $disk.Name -ManagedDiskId $disk.ManagedDisk.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach
    }

#Add NIC(s)
    foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {Add-AzVMNetworkInterface -VM $newVM -Id $NewNic.id}

###############
# CREATE NEW VM
###############

#Recreate the VM
    New-AzVM -ResourceGroupName $NewRGName -Location $originalVM.Location -VM $newVM -Verbose

#******************************************************************************
# PowerShell 7 and Az module End
#******************************************************************************

