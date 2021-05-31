<#
.SYNOPSIS
    Recursively deletes everything in a folder on Azure Files
.DESCRIPTION
    Azure Files does not have a -force option to delete directories (yet). This script van be used to periodically clean files and subfolders
.PREREQUISITES 
    Script requires az.storage module in Automation Account
.PARAMETER StorageAccountName
    Name of the storage account
.PARAMETER StorageAccountKey
   Storage account key
.PARAMETER ShareName
    Name of the file share the direcotry is located in
.PARAMETER BaseDirectory
    Directory to empty 

.NOTES
    Version:        0.5
    Author:         Sven Jambor
    Creation Date:  31-05-2021
    Purpose/Change: initial version
  
.EXAMPLE
    .\Remove-FolderContents.ps1 -StorageAccountName "storageacc" -StorageAccountKey "fehwr347483t34703 [38- o//abQ=="  -ShareName "theshare" -BaseDirectory "temp"
.ToDo
    - Use automation account with connect-azAccount and don't storage account key
    - Add option to dela with age of files (min/max age)
#>

Param (
    [string]$StorageAccountName, #Storage account name" 
    [string]$StorageAccountKey,  #Storage account primary key"
    [string]$ShareName,          #Azure Files Share name
    [string]$BaseDirectory       #Directory you want to empty 
)

function Recursive-Delete(){
    Param (
        $Directory,
        $Context
    )

    $contents = Get-AzStorageFile -Directory $Directory

    foreach ($entry in $contents)
    {   
        if (($entry.GetType().Name -eq "CloudFileDirectory") -or ($entry.GetType().Name -eq  "AzureStorageFileDirectory")) {
            $action = Recursive-Delete -Directory $entry.CloudFileDirectory -Context $Context
        }
        else
        {
            Write-Output "...removing file $($entry.Name)"
            $action = Remove-AzStorageFile -File $entry.CloudFile   
        }
    }

    if($Directory -ne $objCheckDir){
        Write-Output "...removing directory $($Directory.Name)"
        #need to SilentlyContinue as it will try to remove the topmost folder as well
        Remove-AzStorageDirectory -Directory $Directory -ErrorAction SilentlyContinue
    }
} 

$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

   Try{
    [Microsoft.Azure.Storage.File.CloudFileDirectory]$objBaseDir = (Get-AzStorageFile -ShareName $ShareName -Context $storageContext -Path "$BaseDirectory" -ErrorAction Stop).CloudFileDirectory

    if ($objBaseDir.Name -contains $BaseDirectory){
        Write-Output "Recursively deleting contents of $($objBaseDir.name)"
          Try{
            Recursive-Delete -Directory $objBaseDir -Context $storageContext 
         } Catch {Write-Error "Recursive Delete Failed"}
    } else {Write-Output "Directory was not found"}
    Write-Output "All done"
   } Catch {
       Write-Output "BaseDirectory $BaseDirectory could not be found"
       }
 