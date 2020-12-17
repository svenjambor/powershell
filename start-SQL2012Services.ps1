#Set-ExecutionPolicy RemoteSigned
$tempDbDataPath = "D:\Data"
$tempDbLogPath = "D:\Logs"

$SqlServicesToStart = @(
        "SQL Server (MSSQLSERVER)",
        "SQL Server Agent (MSSQLSERVER)",
        "SQL Server Browser",
        "SQL Server Integration Services 11.0",
        "SQL Server VSS Writer")
        

function check-TemdbFolder {

    param (
       [String]$fullPath
    )

    $success = $true

    write-Host "Checking for folder '$fullPath'" 

    if (!(test-path $fullPath)){
        write-Host "... folder not found; creating '$fullPath'"

        try {    
            New-Item -Path $fullPath -ItemType directory -Force -ErrorAction Stop | Out-Null
            Write-Host "Successfully created folder '$fullPath'"
            $success = $true

        } catch {
            Write-Error "Failed to create folder '$fullPath'"
            $success = $false
        }
    } else {Write-Host "... folder exists"} 
    return $success
}

try {

    $dataPathExists = check-TemdbFolder -fullPath $tempDbDataPath -ErrorAction Stop
    $logPathExists = check-TemdbFolder -fullPath $tempDbLogPath -ErrorAction Stop

    if($dataPathExists -and $logPathExists) { 
        Write-Host "TempDB folders exist. Starting SQL"
        foreach($SqlService in $SqlServicesToStart){
            try{
                Write-Host "Starting '$SqlService'..."
                Start-Service -DisplayName $SqlService -ErrorAction Stop
                Write-Host "... done"
                
                } catch {
                Write-Error "...failed!"
            }
          }
       } 
} catch {
         Write-Error "Not all folders exist; not starting SQL"
  }
