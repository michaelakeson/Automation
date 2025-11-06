# This script searches for Test release and deletes older version so new version becomes current version. 

# Perameters to pass in 
    # Project number

Param (
#     [string] $uipathCliFilePath = "" #if not provided, the script will auto download the cli from uipath public feed.
      [string]$ProcessNumber,
      [string]$client_id,
      [string]$client_secret,
      [string]$Tenant

)
#Variables
$folderListEndpoint = "https://cloud.uipath.com/########/$Tenant/orchestrator_/odata/Folders"
$UpdatePackageURL = "https://cloud.uipath.com//########/$/AIGI_Dev/orchestrator_/odata/Releases($ReleaseId)"


Start-Sleep -Seconds 10 # wait 10 sec for orch

# Step 1: Set up variables
Write-Output "Step 1: Set up variables"
$AuthUrl = "https://cloud.uipath.com/identity_/connect/token"

$headers = @{
    "Content-Type" = "application/x-www-form-urlencoded"
}

$body = @{
    "grant_type"= "client_credentials"
    "scope"= "OR.Assets OR.BackgroundTasks OR.Execution OR.Folders OR.Jobs OR.Machines.Read OR.Monitoring OR.Queues OR.Robots.Read OR.Settings.Read OR.TestSetExecutions OR.TestSets OR.TestSetSchedules OR.Users.Read"
    "client_id"= $client_id
    "client_secret"= $client_secret
    
}

$response = Invoke-RestMethod -Uri $AuthUrl -Method Post -Headers $headers -Body $body
$accessToken = $response.access_token #exstract access token



# Step 2: Get list of folders
Write-Output "Step 2: Get list of folders"
$folderListEndpoint = "https://cloud.uipath.com/########/$Tenant/orchestrator_/odata/Folders"

$headers = @{
    "Authorization" = "Bearer $accessToken"
}

$response = Invoke-RestMethod -Uri $folderListEndpoint -Headers $headers -Method Get

# Get ONLY the folder with DisplayName 'Shared'
$sharedFolder = $response.value | Where-Object { $_.DisplayName -eq "Shared" }

if (-not $sharedFolder) {
    Write-Output "Shared folder not found!"
    exit
}

$sharedFolderId = $sharedFolder.Id

# Step 3: Get release ID for only Shared folder
Write-Output "Step 3: Get release ID"
Write-Output "Process Key starts with '$ProcessNumber'"

# Set headers for API request
$headers = @{
    "X-UIPATH-OrganizationUnitId" = "$sharedFolderId"
    "Authorization" = "Bearer $accessToken"
}

$response = Invoke-RestMethod -Uri $ReleaseURL -Headers $headers -Method Get

if ($response.value) {
    # Filter: starts with process number AND does not contain 'Tests'
    $filteredResults = $response.value | Where-Object { 
        $_.ProcessKey -like ($ProcessNumber + '*') -and $_.ProcessKey -match 'Tests'
    }

    foreach ($item in $filteredResults) {
        $ReleaseId = $item.Id
        $organizationUnitId = $item.OrganizationUnitId
        Write-Output "Id: $ReleaseId - $organizationUnitId"
    }
}


# Step 4: Loop through release ID and upgrade-
Write-Output "Step 4: Loop through release ID and Delete Test"
if ($ReleaseId) {
    Write-Output "ReleaseId is not null or empty: $ReleaseId"
    $headers = @{
    "X-UIPATH-OrganizationUnitId" = "$organizationUnitId"
    "Authorization" = "Bearer $accessToken"
    } 
    $response = Invoke-RestMethod -Uri $UpdatePackageURL -Headers $headers -Method DELETE
    Write-Output "$response"

} else {
    Write-Output "ReleaseId is null or empty"
}





Write-Output "Completed"
