#Set-ExecutionPolicy RemoteSigned
$tempDbDataPath = "D:\Data"
$tempDbLogPath = "D:\Log"

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

    write-verbose "Checking for folder '$fullPath'" 

    if (!(test-path $fullPath)){
        write-verbose "... folder not found; creating '$fullPath'"

        try {    
            New-Item -Path $fullPath -ItemType directory -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Successfully created folder '$fullPath'"
            $success = $true

        } catch {
            Write-Error "Failed to create folder '$fullPath'"
            $success = $false
        }
    }
    return $success
}

$startSQL = $false
try {

    $dataPathExists = check-TemdbFolder -fullPath $tempDbDataPath -ErrorAction Stop | Out-Null
    $logPathExists = check-TemdbFolder -fullPath $tempDbLogPath -ErrorAction Stop | Out-Null

    if($dataPathExists -and $logPathExists) { $startSQL = $true }  
    } catch {
         Write-Error "Not all folders exist; not starting SQL"
    }

if($startSQL){
    Write-Verbose "Starting SQL Services"
    foreach($SqlService in $SqlServicesToStart){
    Start-Service -DisplayName $SqlService
    }
}
