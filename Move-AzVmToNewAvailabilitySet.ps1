<#
.SYNOPSIS
   Move Azure VM to an Availability Set
.DESCRIPTION
    Deallocates and redeploys an Azure VM to move it into a new Availbility Set.
    This Will create the Availability Set if not found.
.EXAMPLE
    PS C:\> ./Move-AzVmToNewAvailabilitySet.ps1 -resourceGroup "prismrbs-prod-eus-rg" -vmName "di-vm0" -newAvailSetName "di-vmSet"
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    # Resource Group Name
    [Parameter(Mandatory)]
    [String]
    $resourceGroup,
    # Virtual Machine Name
    [Parameter(Mandatory)]
    [String]
    $vmName,
    # Availability Set Name
    [Parameter(Mandatory)]
    [String]
    $newAvailSetName,
    # Availability Set Fault Domain Count
    [Parameter(Mandatory=$False)]
    [Int]
    $FaultDomainCount = 2,
    # Availability Set Update Domain Count
    [Parameter(Mandatory=$False)]
    [Int]
    $UpdateDomainCount = 2,
    # Force
    [Parameter(Mandatory=$False)]
    [Switch]
    $Force = $false
)


if ($PSCmdlet.ShouldProcess("$vmName", "Deallocate and Redeploy VM into Availability Set [$newAvailSetName]")) {
        
    Write-Verbose "Retrieving Details from existing VM"
    # Get the details of the VM to be moved to the Availability Set
    $originalVM = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName -ErrorAction Stop

    # Create new availability set if it does not exist
    $availSet = Get-AzAvailabilitySet `
        -ResourceGroupName $resourceGroup `
        -Name $newAvailSetName `
        -ErrorAction Ignore

    if (-Not $availSet) {
        Write-Verbose "Availability Set not found. Creating."
        $availSet = New-AzAvailabilitySet `
            -Location $originalVM.Location `
            -Name $newAvailSetName `
            -ResourceGroupName $resourceGroup `
            -PlatformFaultDomainCount $FaultDomainCount `
            -PlatformUpdateDomainCount $UpdateDomainCount `
            -Sku Aligned
    }

    Write-Verbose "Deallocating VM"
    # Remove the original VM
    Remove-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force:$Force

    # Create the basic configuration for the replacement VM
    $newVM = New-AzVMConfig `
        -VMName $originalVM.Name `
        -VMSize $originalVM.HardwareProfile.VmSize `
        -AvailabilitySetId $availSet.Id `
        -Tags $originalVM.Tags

    Set-AzVMOSDisk `
        -VM $newVM -CreateOption Attach `
        -ManagedDiskId $originalVM.StorageProfile.OsDisk.ManagedDisk.Id `
        -Name $originalVM.StorageProfile.OsDisk.Name `
        -Windows | Out-Null

    # Add Data Disks
    foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
        Add-AzVMDataDisk -VM $newVM `
            -Name $disk.Name `
            -ManagedDiskId $disk.ManagedDisk.Id `
            -Caching $disk.Caching `
            -Lun $disk.Lun `
            -DiskSizeInGB $disk.DiskSizeGB `
            -CreateOption Attach | Out-Null
    }

    # Add NIC(s) and keep the same NIC as primary
    foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {	
        if ($nic.Primary -eq "True") {
            Add-AzVMNetworkInterface `
                -VM $newVM `
                -Id $nic.Id -Primary | Out-Null
        }
        else {
            Add-AzVMNetworkInterface `
                -VM $newVM `
                -Id $nic.Id | Out-Null
        }
    }

    Write-Verbose "Deploying new VM instance."
    # Recreate the VM
    New-AzVM `
        -ResourceGroupName $resourceGroup `
        -Location $originalVM.Location `
        -VM $newVM

}
