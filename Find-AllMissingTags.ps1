<#
.SYNOPSIS
Finds all resource groups and resources missing tags. 

.DESCRIPTION
Finds all resource groups and resources missing tags.

.PARAMETER Environment
Sets the Azure subscription name of the subscription to review.

.PARAMETER SubscriptionId
Sets the Azure subscription Id of the subscription to review. 

.PARAMETER TenantId
Sets the Azure Tenant to use. 

.PARAMETER SubscriptionName
Sets the Azure subscription name of the subscription to review. 

.PARAMETER AllSubscriptions
Switch used to specify all subscriptions should be reviewed.

.PARAMETER Path
Sets the file path to the .json file to save to. Path should be a *.json filename.

.PARAMETER ExcludeSubscription
Sets the subscirption names to exclude from review. 

.EXAMPLE
PS>  Find-AllMissingTags -AllSubscriptions -Path C:\findings.json
Finds all Azure resource groups and resources missing tags and exports the results to the specified *.json file.

.EXAMPLE
PS>  Find-AllMissingTags -SubscriptionName "ABC"
Finds all Azure resource groups and resources missing tags from the provided subscription name and displays the results in the console. 

.EXAMPLE
PS>  Find-AllMissingTags -AllSubscriptions -ExcludeSubscription "CDE","FGH" -Path C:\findings.json
Finds all Azure resource groups and resources missing tags from all subscription name, but excludes the specified subscriptions,and exports the results to the specified *.json file. 

#>
[CmdletBinding()]
param(

    # Sets the cloud environment. This parameter is restricted to a validated set of values. 
    [Parameter()]
    [String]
    [ValidateSet('AzureCloud', 'AzureUSGovernment', 'AzureChinaCloud')]
    $Environment = "AzureCloud", 

    # Sets the Tenant ID where the Azure subscription are associated to. 
    [Parameter()]
    [String]
    $TenantId, 

    # Sets the subscription Id for subscription(s) to check.
    [Parameter()]
    [String[]]
    $SubscriptionId,

    # Sets the subscription name for subscription(s) to check.
    [Parameter()]
    [String[]]
    $SubscriptionName,

    # Checks all subscriptions. 
    [Switch]
    $AllSubscriptions,

    # Sets the file path to the .json file to save to. Path should be a *.json filename. 
    [Parameter()]
    [System.IO.FileInfo]
    $Path, 

    # Sets the subscirption names to exclude from this process. 
    [Parameter()]
    [String[]]
    $ExcludeSubscription
)

try {


    # Connect to Azure. 
    if($TenantId) {

        $AzConnect = @{
            Environment = $Environment
            Tenant = $TenantId
        }
    } else {
        $AzConnect = @{
            Environment = $Environment
        }
    }

    try {
        Write-Host "Connecting to Azure"
        Connect-AzAccount @AzConnect -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    } catch {
        throw "Unable to connect to Azure using the provided information! $($_)"
    }
    # End connect to Azure.

    # Get and set subscription information.
    $Subscriptions = @()

    Write-Host "Setting subscription object(s) to pull resources from." 
    if($AllSubscriptions.IsPresent) {
        $Subscriptions = Get-AzSubscription -ErrorAction Stop -WarningAction SilentlyContinue
    } elseif($SubscriptionId) {

        try {
            $SubscriptionId | ForEach-Object { $Subscriptions += $(Get-AzSubscription -SubscriptionId $_ -WarningAction SilentlyContinue -ErrorAction Stop) }
        } catch {
            throw "Unable to obtain subscriptions by Id! $($_)"
        }
    } else {

        try {
            $SubscriptionName | ForEach-Object { $Subscriptions += $(Get-AzSubscription -SubscriptionName $_ -WarningAction SilentlyContinue -ErrorAction Stop) }
        } catch {
            throw "Unable to obtain subscription by name! $($_)"
        }
    }

    # End get and set subscription information.

    # Declare a storage object
    $SubscriptionObject = New-Object 'System.Collections.Generic.List[PSObject]'

    #Start loop for subscription iteration
    $Subscriptions | ForEach-Object {

        $Subscription = $_

        if($Subscription.Name -in $ExcludeSubscription) {
            Write-Host "Skipping $($Subscription.Name), subscription is excluded."
        } else {
            Write-Host "Processing $($Subscription.Name)"
            try {
                Write-Verbose "Setting context to $($Subscription.Name)."
                Set-AzContext -Subscription $Subscription.Name -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            } catch {
                throw "Fail to set the subscription context! $($_)"
            }

            Write-Verbose 'Get missing tags for Resource Groups'
            $AllResourceGroups = Get-AzResourceGroup | Where-Object { $null -eq $_.Tags -or $_.Tags.Count -eq 0 }

            Write-Verbose 'Get missing tags for all resources (excludes hidden resources.)'
            $AllResources = Get-AzResource | Where-Object { $null -eq $_.Tags -or $_.Tags.Count -eq 0 -and $_ -notlike 'hidden-*' }

            $SubscriptionObject.Add([PSCustomObject]@{
                    SubscriptionName  = $Subscription.Name
                    ResourceGroupName = $AllResourceGroups | ForEach-Object { 
                        if ($AllResourceGroups.Count -gt 1) {
                            if ($AllResourceGroups.IndexOf($_) -eq ($AllResourceGroups.Count - 1)) { 
                                $($_.ResourceGroupName) 
                            } else { 
                                $($_.ResourceGroupName + ',') 
                            } 
                        } else {
                            $($_.ResourceGroupName)
                        }
                    }
                    ResourceName      = $AllResources | ForEach-Object { 
                        if ($AllResources.Count -gt 1) {
                            if ($AllResources.IndexOf($_) -eq ($AllResources.Count - 1)) { 
                                $($_.Name) 
                            } else { 
                                $($_.Name + ',') 
                            } 
                        } else {
                            $($_.Name)
                        }
    
                    }
                })
        }
    }    

    if($Path) {
        try {
            Write-Host "Exporting results to $($Path)"
            $SubscriptionObject | ConvertTo-Json -Depth 1 | Set-Content -Path $Path -ErrorAction Stop
            Write-Host 'Export complete!'
        } catch {
            throw "Failed to export to $($Path)! $($_)"
        }
    } else {

        $SubscriptionObject | Format-Table

    }

} catch {
    throw "An unexpected error has occurred! $($_)"
}