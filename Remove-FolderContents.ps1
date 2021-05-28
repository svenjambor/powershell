Param (
    [string]$StorageAccountName, #Storage account name" 
    [string]$StorageAccountKey,  #Storage account primary key"
    [string]$ShareName,          #Azure Files Share name
    [string]$BaseDirectory       #Directory you want to empty 
)

Process {

    function Recursive-Delete(){
        Param (
           $Directory,
           $Context
        )

        $contents = Get-AzStorageFile -Directory $Directory

        foreach ($entry in $contents)
        {   
            $entry.GetType().Name
            if (($entry.GetType().Name -eq "CloudFileDirectory") -or ($entry.GetType().Name -eq  "AzureStorageFileDirectory")) {
                Recursive-Delete -Directory $entry.CloudFileDirectory -Context $Context
            }
            else
            {
                #"removing file $($entry.Name)"
                Remove-AzStorageFile -File $entry.CloudFile   
            }
        }

        if($Directory -ne $objCheckDir){
            #"removing directory $($Directory.Name)"
            Remove-AzStorageDirectory -Directory $Directory -ErrorAction SilentlyContinue
        }
    } 

    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

    Try{
        [Microsoft.Azure.Storage.File.CloudFileDirectory]$objBaseDir = (Get-AzStorageFile -ShareName $ShareName -Context $storageContext -Path "$BaseDirectory" -ErrorAction Stop).CloudFileDirectory
        if ($objBaseDir.Name -contains $BaseDirectory){
            Write-Information "Recursively deleting contents of $($objBaseDir.name)"
            Try{
                Recursive-Delete -Directory $objBaseDir -Context $storageContext 
            } Catch {Write-Error "Recursive Delete Failed"}
        } else {Write-Error "Directory was not found"}
        Write-Information "All done"
    } Catch {
        Write-Error "BaseDirectory $BaseDirectory could not be found"
        break
        }
}
