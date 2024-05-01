<#
.SYNOPSIS
Create a VNet link to all Private DNS Zones. Recommended for a centralized Azure Private DNS setup. 

.DESCRIPTION
Creates a Virtual Network (VNet) link for each VNet that exists within a subscription, and associates it with all the private DNS zones available in a tenant—recommended for a centralized Azure Private DNS setup. 

.PARAMETER PrivateDnsZones
Holds an array of Private DNS Zone names. If not specified the default will be to pull Private DNS Zone name from the subscription specified in the SubscriptionName parameter. 

.PARAMETER ResourceGroupName
The name of the resource group with the Private DNS Zones. 

.PARAMETER SubscriptionName
The subscription name with the Private DNS Zones.

.PARAMETER ExcludeSubscription
An array of subscription names to exclude. 

.PARAMETER ExcludePrivateDnsZone
An array of Private DNS Zone names to exclude.

.EXAMPLE
.\Set-AzPrivateDnsZone.ps1 -ResourceGroupName "rg-PrivateDNSZones" -SubscriptionName "Management" -TenantId "x0000000-x00x-0000-xx00-00xxxxxxx0x0"

Will pull all VNets within all subscriptions and create a VNet link to all Private DNS Zones. 

.EXAMPLE
.\Set-AzPrivateDnsZone.ps1 -ResourceGroupName "rg-PrivateDNSZones" -SubscriptionName "Management" -TenantId "x0000000-x00x-0000-xx00-00xxxxxxx0x0" -ExcludeSubscription "Human Resource","Identity"

Will pull all VNets within all subscriptions except for the Human Resource and Identity subscription and create a VNet link to all Private DNS Zones.

.EXAMPLE
.\Set-AzPrivateDnsZone.ps1 -ResourceGroupName "rg-PrivateDNSZones" -SubscriptionName "Management" -TenantId "x0000000-x00x-0000-xx00-00xxxxxxx0x0" -ExcludePrivateDnsZone "privatelink.database.windows.net","privatelink.monitor.azure.com"

Will pull all VNets within all subscriptions and create a VNet link to all Private DNS Zones except for privatelink.database.windows.net and privatelink.monitor.azure.com
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(HelpMessage="Enter Private DNS Zone names.")]
    [String[]]
    $PrivateDnsZones,

    [Parameter(Mandatory, HelpMessage="Enter the resource group name where the private dns zones reside.")]
    [String]
    $ResourceGroupName,


    [Parameter(Mandatory, HelpMessage="Enter the subscription name where the private dns zones reside.")]
    [String]
    $SubscriptionName,

    [Parameter(Mandatory, HelpMessage="Enter the Azure tenant Id.")]
    [String]
    $TenantId,

    # Subscriptions to exclude from discovery.
    [Parameter(HelpMessage="Enter subscription names that can be excluded from the subscription name discovery.")]
    [String[]]
    $ExcludeSubscription,

    [Parameter(HelpMessage="Enter Private DNS Zone names that can be excluded from the private dns zone names discovery.")]
    [String[]]
    $ExcludePrivateDnsZone, 

    [Parameter(HelpMessage="Enter Virtual Network names that can be excluded.")]
    [String[]]
    $ExcludeVNetName
)

# Script error handling. 
trap [System.Exception] { 
    "An unexpected error has occurred! $($_)"
    break 
}


# Login into Azure
Connect-AzAccount -Tenant $TenantId -WarningAction Ignore -ErrorAction Stop | Out-Null

# Set context to the subscription that holds the private dns zones. 
Set-AzContext $SubscriptionName -WarningAction Ignore -ErrorAction Stop | Out-Null


Write-Verbose "Get all Private DNS Zone names"
if($PrivateDnsZones) {
    $AllPrivateDnsZoneNames = $PrivateDnsZones
} else {
    $AllPrivateDnsZoneNames = $(Get-AzPrivateDnsZone -ErrorAction Stop | Where-Object { $_.Name -notin $ExcludePrivateDnsZone }).Name
}

Write-Verbose "Get all subscription names"
$allSubscriptions = Get-AzSubscription -WarningAction Ignore -ErrorAction Stop | Where-Object { $_.Name -notin $ExcludeSubscription }

$vnetProperties = New-Object System.Collections.Generic.List[PSObject]

$allSubscriptions | ForEach-Object {

    $subName = $_.Name

    Set-AzContext $subName -WarningAction Ignore -ErrorAction Stop | Out-Null

    $VNET = Get-AzVirtualNetwork

    if($VNET) {
        $VNET | ForEach-Object {
            if($_.Name -notin $ExcludeVNetName) {
                Write-Verbose "`nAdding entry"
                Write-Verbose "Subscription: $($subName)"
                Write-Verbose "VNet: $($_.Name)"
                Write-Verbose "VNetId: $($_.Id)"  
                              
                $vnetProperties.Add(
                [PSCustomObject]@{
                    subscriptionName = $subName
                    vnetName = $_.Name
                    vnetId = $_.Id

                })
            }
        }
    }
}

Write-Verbose "Context changed to $($SubscriptionName)"
Set-AzContext $SubscriptionName -WarningAction Ignore -ErrorAction Stop | Out-Null

$vnetProperties | ForEach-Object {
    $sub = $_.subscriptionName
    $Name = $_.vnetName
    $Id = $_.vnetId
    
    $linkName = "link-to-$($Name)"
    $vNetId = $Id

    $AllPrivateDnsZoneNames | ForEach-Object {

        Write-Host "`nZoneName: $($_)"

        $Existing = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $ResourceGroupName -ZoneName $_  -ErrorAction SilentlyContinue | Where-Object { $_.VirtualNetworkId -eq $vNetId }

        if($Existing) {
            Write-Host "Removing the existing link."
            #Remove-AzPrivateDnsVirtualNetworkLink -ResourceId $($Existing).ResourceId -ErrorAction Stop
        } 

        Write-Host "Subscription: $($sub)"
        Write-Host "Link Name: $($linkName) & ID: $($vNetId)"
        #New-AzPrivateDnsVirtualNetworkLink -ZoneName $_ -ResourceGroupName $ResourceGroupName -Name $linkName -VirtualNetworkId $vNetId -ErrorAction Stop | Out-Null
    }

}
