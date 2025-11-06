param (
    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowFilePath,

    [Parameter(Mandatory = $true)]
    [string]$ProjectNumber,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowName,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowCredentials,

    [Parameter(Mandatory = $false)]
    [string]$Environment = "dev"
)

if ($Environment -eq "dev") {
    # Base URL for Alteryx API
    $baseUrl = "https://alteryx-dev.#########.io/webapi/v3"
    $tokenUrl = "https://alteryx-dev.########.io/webapi/oauth2/token"
    $ownerId = "####################"
}
else {
    Write-Host "Running in unknown environment: $Environment"
    $baseUrl = "https://alteryx.#########.io/webapi/v3"
    $tokenUrl = "https://alteryx.#########.io/webapi/oauth2/token"
    $ownerId = "#######################"
}




# Prepare body for the request
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
}

# Make the request
try {
    $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded"

    # Assign token to variable
    $BearerToken = $response.access_token


}
catch {
    Write-Error "Failed to retrieve token. $_"
}
#-----------------------------------------------------------------------------------------------------------------



# Headers for API requests----------------------------------------------------------------------------------------
$headers = @{
    "accept" = "application/json"
    "authorization" = "Bearer $BearerToken"
}


# Function to handle API errors---------------------------------------------------------------------------------
function Handle-ApiError {
    param (
        [string]$Message,
        [System.Net.HttpWebResponse]$Response
    )
    Write-Error "$Message. Status: $($Response.StatusCode) - $($Response.StatusDescription)"
    exit 1
}





# Step 1: Get Credential ID----------------------------------------------------------------------------------------
    Write-Host "Fetching Credential ID..."
    $credentialsUri = "$baseUrl/credentials"
    $credentialsResponse = Invoke-RestMethod -Uri $credentialsUri -Method Get -Headers $headers -ErrorAction Stop
    
    # Find the credential matching the WorkflowCredentials value
    $credential = $credentialsResponse | Where-Object {
        $_.userName.Trim().ToLower() -like "*$($WorkflowCredentials.Trim().ToLower())*"
    }
    
    if (-not $credential) {
        Write-Error "No matching credential found for WorkflowCredentials: $WorkflowCredentials"
        exit 1
    }
    
    $credentialId = $credential.id
    Write-Host "Credential ID: $credentialId"

# Step 2: Get Workflow ID and Owner ID
Write-Host "Fetching Workflow and Owner ID for project $ProjectNumber..."
$workflowUri = "$baseUrl/workflows?view=Default&name=$ProjectNumber"
$workflowResponse = Invoke-RestMethod -Uri $workflowUri -Method Get -Headers $headers -ErrorAction Stop

if (-not $workflowResponse -or $workflowResponse.Count -eq 0) {
    Write-Warning "No workflow found for project $ProjectNumber."
    $WorkflowNotFound = "yes"
}
else {
    # Assuming the first workflow matching the name is the one we need
    $workflowId = $workflowResponse[0].id
    $ownerId2   = $workflowResponse[0].ownerId

    if (-not $workflowId -or -not $ownerId -or $ownerId -ne $ownerId2) {
        Write-Warning "No Workflow ID or Owner ID found for project $ProjectNumber."
        $WorkflowNotFound = "Yes"
    }
    else {
        Write-Host "Workflow ID: $workflowId"
        Write-Host "Owner ID: $ownerId"
        $WorkflowNotFound = "No"
    }
}
Write-Host "WorkflowNotFound = $WorkflowNotFound"



if ($WorkflowNotFound -eq "Yes") {
    Write-Host "Deploy New workflow"
    Write-Host "Create New Workflow"
    
    # Step: Upload brand new workflow using curl.exe
    Write-Host "Creating new workflow for project $ProjectNumber..."
    
    $workflowFile = "$WorkflowFilePath"
    $workflowNameEscaped = $WorkflowName -replace ' ', '\ '
    $uploadUri = "$baseUrl/workflows"
    
    try {
        $curlCommand = @(
            "curl.exe",
            "-X POST",
            "'$uploadUri'",
            "-H 'accept: application/json'",
            "-H 'authorization: Bearer $BearerToken'",
            "-H 'Content-Type: multipart/form-data'",
            "-F 'file=@$workflowFile;type=application/yxzp'",
            "-F 'name=$workflowName'",
            "-F 'ownerId=$ownerId'",
            "-F 'isPublic=false'",
            "-F 'isReadyForMigration=false'",
            "-F 'othersMayDownload=true'",
            "-F 'othersCanExecute=true'",
            "-F 'executionMode=Standard'",
            "-F 'workflowCredentialType=Specific'",
            "-F 'credentialId=$credentialId'",
            "-s",       # silent: hide progress
            "-o nul",   # discard response body
            "-w '%{http_code}'"  # only output HTTP code
        ) -join " "
    
    }
    catch {
        Write-Error "Error occurred during workflow creation: $_"
        exit 1
    }
}
else {
    Write-Host "Update Existing Workflow"
    # Step 3: Upload new version of the workflow using curl.exe
    Write-Host "Uploading new workflow version for project $ProjectNumber..."
    
    $workflowFile = "$WorkflowFilePath"
    $workflowNameEscaped = $WorkflowName -replace ' ', '\ '
    $uploadUri = "$baseUrl/workflows/$workflowId/versions"

    try {
        $curlCommand = @(
            "curl.exe",
            "-X POST",
            "'$uploadUri'",
            "-H 'accept: application/json'",
            "-H 'authorization: Bearer $BearerToken'",
            "-F 'file=@$workflowFile;type=application/yxzp'",
            "-F 'name=$workflowName'",
            "-F 'ownerId=$ownerId'",
            "-F 'othersMayDownload=true'",
            "-F 'othersCanExecute=true'",
            "-F 'executionMode=Standard'",
            "-F 'hasPrivateDataExemption=false'",
            "-F 'makePublished=true'",
            "-F 'workflowCredentialType=Specific'",
            "-F 'credentialId=$credentialId'",
            "-s",       # silent: hide progress
            "-o nul",   # discard response body
            "-w '%{http_code}'"  # only output HTTP code
        ) -join " "
        
    }
    catch {
        Write-Error "Error occurred during workflow upload: $_"
        exit 1
    }
}


# Run curl
$httpCode = Invoke-Expression $curlCommand
$httpCode = $httpCode.Trim()   # should now be just 200 or 201

Write-Host "  "
Write-Host "Response: $httpCode"
Write-Host "  "


# Check success
if ($httpCode -eq "200" -or $httpCode -eq "201") {
    Write-Host "Upload successful"
    exit 0
} else {
    Write-Host "Failed with HTTP code $httpCode"
    exit 1
}
