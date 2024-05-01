<#
.SYNOPSIS
Finds and removes unknown role assignments. 

.DESCRIPTION
Find and removes all unknown role assigments in an Azure subscription. 

.PARAMETER SubscriptionName
Sets the Azure subscription name of the subscription to review.

.PARAMETER SubscriptionId
Sets the Azure subscription Id of the subscription to review. 

.PARAMETER TenantId
Sets the Azure Tenant to use. 

.PARAMETER QuotaIdContains
Sets the QuotaId name of the subscription type. 

.PARAMETER QuotaIdExclude
Sets the exclusions of the subscription type.

.PARAMETER All
Bool to review all subscriptions. 

.EXAMPLE
PS>  Remove-AzTypeUnknownRoleAssignmentt -All
Reviews all subscriptions for unknown role assignments and removes the found unkown role assignments.

.EXAMPLE
PS>  Remove-AzTypeUnknownRoleAssignment -SubscriptionName "ABC" -TenantId "123-456-789-000"
Reviews the specified subscription for unknown role assignments and removes the found unknown role assignments. 

.EXAMPLE
PS>  Remove-AzTypeUnknownRoleAssignment -SubscriptionId "ABC" -TenantId "123-456-789-000"
Reviews the specified subscription for unknown role assignments and removes the found unknown role assignments. 

.EXAMPLE
PS>  Remove-AzTypeUnknownRoleAssignment -SubscriptionName "ABC" -TenantId "123-456-789-000" -QuotaIdContains "Enterprise"
Reviews the specified subscription for unknown role assignments and only removes the found unknown role assignments if the subscription quota type contains Enterprise.

.EXAMPLE
PS>  Remove-AzTypeUnknownRoleAssignment -SubscriptionName "ABC" -TenantId "123-456-789-000" -QuotaIdExclude Enterprise,DevTest
Reviews the specified subscription for unknown role assignments and only removes the found unknown role assignment if the subscription type is not in the provided exclusion list. 
#>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$SubscriptionName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$TenantId,

        [Parameter()]
        [Switch]$All,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$QuotaIdContains,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]]$QuotaIdExclude
    )


    Write-Verbose "**********"
    Write-Verbose "PARAMETERS"
    Write-Verbose "`tSUBSCRIPTIONNAME = $SubscriptionName"
    Write-Verbose "`tSUBSCRIPTIONID = $SubscriptionId"
    Write-Verbose "`t-ALL = $($All.IsPresent)"
    Write-Verbose "`tQUOTAIDCONTAINS = $QuotaIdContains"
    Write-Verbose "`tQUOTAIDEXCLUDE = $($QuotaIdExclude -join ',')"
    Write-Verbose "**********`n"


    try {
        [void](Connect-AzAccount)
    } catch {
        Write-Host "$(Get-Date)`tCould not connect to Azure. $($_)" -ForegroundColor Red
        exit
    }

    try {
        try {
            Write-Host "$(Get-Date)`tRetrieving subscription information..."
            if ($All.IsPresent) {
                Write-Verbose "$(Get-Date)`tALL parameter switch used."
                $Subscriptions = Get-AzSubscription -ErrorAction Stop
            } else {
                if ($SubscriptionId) {
                    Write-Verbose "$(Get-Date)`tSubscriptionId parameter used."
                    $Subscriptions = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
                } else {
                    Write-Verbose "$(Get-Date)`tSubscriptionName parameter used."
                    $Subscriptions = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Stop
                }
            }

        } catch {
            Write-Host "$(Get-Date)`tCould not get the subscription information from the provided subscription parameter. $($_)"
            exit
        }

        if($Subscriptions.Count -ge 1) {

            try {

                Write-Verbose "$(Get-Date)`t$($Subscriptions.Count) Subscriptions"
                $Subscriptions | ForEach-Object {
                    $subObj = $_
                    Write-Host "$(Get-Date)`tSetting context to $($subObj.Name)"
                    [void](Set-AzContext -SubscriptionName $_.Name -ErrorAction Stop)

                    $AllUnknown = Get-AzRoleAssignment | Where-Object { $_.ObjectType.Equals("Unknown") } 
                    if($AllUnknown.Count -ge 1) {
                        Write-Host "$($AllUnknown.Count) unknown role assignments found in $($subObj.Name)"
                        if ($subObj.SubscriptionPolicies.QuotaId -like "*$QuotaIdContains*" -and $subObj.SubscriptionPolicies.QuotaId -notin $QuotaIdExclude) {

                            $AllUnknown | ForEach-Object {
                                Write-Host "Removing unknown role assignment with ObjectId, $($_.ObjectId)"
                                Remove-AzRoleAssignment -ObjectId $_.ObjectId -RoleDefinitionName $_.RoleDefinitionName -Scope $_.Scope -ErrorAction Stop
                        
                            }

                        } else {
                            Write-Verbose "Skipping $($subObj.Name) the QuotaId is $($subObj.SubscriptionPolicies.QuotaId)"
                        }
                    } else {
                        Write-Host "$(Get-Date)`t$($subObj.Name) has no unknown role assignments to remove"
                    }
                }
            } catch {
                Write-Host "$(Get-Date)`tCould not remove unknown role assignments for the $($subObj.Name). $($_)"
                exit
            }
            
        } else {
            Write-Host "$(Get-Date)`tNo subscription data was retrieved."
        }

    } catch {
        Write-Host "$(Get-Date)`tAn unexpected error has occurred. $($_)"
    }
