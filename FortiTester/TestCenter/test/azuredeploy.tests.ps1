#Requires -Modules Pester
<#
.SYNOPSIS
    Tests a specific ARM template
.EXAMPLE
    Invoke-Pester
.NOTES
    This file has been created as an example of using Pester to evaluate ARM templates
#>

param (
    [string]$sshkey,
    [string]$sshkeypub
)
$VerbosePreference = "Continue"

BeforeAll {
    $templateName = "TestCenter"
    $sourcePath = "$env:GITHUB_WORKSPACE\FortiTester\$templateName"
    $scriptPath = "$env:GITHUB_WORKSPACE\FortiTester\$templateName\test"
    $templateFileName = "mainTemplate.json"
    $templateFileLocation = "$sourcePath\$templateFileName"
    $templateParameterFileName = "mainTemplate.parameters.json"
    $templateParameterFileLocation = "$sourcePath\$templateParameterFileName"

    # Basic Variables
    $testsRandom = Get-Random 10001
    $testsPrefix = "FORTIQA"
    $testsResourceGroupName = "FORTIQA-$testsRandom-$templateName"
    $testsAdminUsername = "azureuser"
    $testsResourceGroupLocation = "westeurope"

    # ARM Template Variables
    $publicIP1Name = "$testsPrefix-FTS-CLIENT-PIP"
    $publicIP2Name = "$testsPrefix-FTS-SERVER-PIP"
    $params = @{ 'adminUsername' = $testsAdminUsername
        'adminPassword'          = $testsResourceGroupName
        'fortiTesterNamePrefix'  = $testsPrefix
        'publicIP1Name'          = $publicIP1Name
        'publicIP2Name'          = $publicIP2Name
    }
    $ports = @(443, 22)
}

Describe 'FTS TestCenter' {
    Context 'Validation' {
        It 'Has a JSON template' {
            $templateFileLocation | Should -Exist
        }

        It 'Has a parameters file' {
            $templateParameterFileLocation | Should -Exist
        }

        It 'Converts from JSON and has the expected properties' {
            $expectedProperties = '$schema',
            'contentVersion',
            'parameters',
            'resources',
            'variables'
            $templateProperties = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | % Name
            $templateProperties | Should -Be $expectedProperties
        }

        It 'Creates the expected Azure resources' {
            $expectedResources = 'Microsoft.Resources/deployments',
            'Microsoft.Storage/storageAccounts',
            'Microsoft.Network/virtualNetworks',
            'Microsoft.Network/networkSecurityGroups',
            'Microsoft.Network/publicIPAddresses',
            'Microsoft.Network/publicIPAddresses',
            'Microsoft.Network/networkInterfaces',
            'Microsoft.Network/networkInterfaces',
            'Microsoft.Network/networkInterfaces',
            'Microsoft.Network/networkInterfaces',
            'Microsoft.Compute/virtualMachines',
            'Microsoft.Compute/virtualMachines'
            $templateResources = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Resources.type
            $templateResources | Should -Be $expectedResources
        }

        It 'Contains the expected parameters' {
            $expectedTemplateParameters = 'acceleratedNetworking',
            'adminPassword',
            'adminUsername',
            'fortinetTags',
            'fortiTesterImageSKU',
            'fortiTesterImageVersion',
            'fortiTesterNamePrefix',
            'instanceType',
            'location',
            'publicIP1Name',
            'publicIP1NewOrExistingOrNone',
            'publicIP1ResourceGroup',
            'publicIP1SKU',
            'publicIP1Type',
            'publicIP2Name',
            'publicIP2NewOrExistingOrNone',
            'publicIP2ResourceGroup',
            'publicIP2SKU',
            'publicIP2Type',
            'serialConsole',
            'subnet1Name',
            'subnet1Prefix',
            'subnet1StartAddress',
            'subnet2Name',
            'subnet2Prefix',
            'subnet2SecondaryIPCount',
            'subnet2StartAddress',
            'subnet3Name',
            'subnet3Prefix',
            'subnet3SecondaryIPCount',
            'subnet3StartAddress',
            'vnetAddressPrefix',
            'vnetName',
            'vnetNewOrExisting',
            'vnetResourceGroup'
            $templateParameters = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Parameters | Get-Member -MemberType NoteProperty | % Name | Sort-Object
            $templateParameters | Should -Be $expectedTemplateParameters
        }

    }

    Context 'Deployment' {

        It "Test Deployment" {
            New-AzResourceGroup -Name $testsResourceGroupName -Location "$testsResourceGroupLocation"
            $resultTest = Test-AzResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileLocation" -TemplateParameterObject $params
            Write-Host ("Test Deployment state: " + $resultTest.Details | Out-String)
            $resultTest.Count | Should -Not -BeGreaterThan 0
        }
        It "Deployment" {
            Write-Host ( "Deployment name: $testsResourceGroupName" )

            $resultDeployment = New-AzResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileLocation" -TemplateParameterObject $params
            Write-Host ($resultDeployment | Format-Table | Out-String)
            Write-Host ("Deployment state: " + $resultDeployment.ProvisioningState | Out-String)
            $resultDeployment.ProvisioningState | Should -Be "Succeeded"
        }
        It "Search deployment" {
            $result = Get-AzVM | Where-Object { $_.Name -like "$testsPrefix*" }
            Write-Host ($result | Format-Table | Out-String)
            $result | Should -Not -Be $null
        }
    }

    Context 'Deployment test' {

        BeforeAll {
            $FTSC = (Get-AzPublicIpAddress -Name $publicIP1Name -ResourceGroupName $testsResourceGroupName).IpAddress
            Write-Host ("FortiTester Client Public IP: " + $FTSC)
            $FTSS = (Get-AzPublicIpAddress -Name $publicIP2Name -ResourceGroupName $testsResourceGroupName).IpAddress
            Write-Host ("FortiTester Server Public IP: " + $FTSS)
        }
        It "FTS: Ports listening" {
            ForEach ( $port in $ports ) {
                Write-Host ("FTS Client - Check port: $port" )
                $portListening = (Test-Connection -TargetName $FTSC -TCPPort $port -TimeoutSeconds 100)
                $portListening | Should -Be $true
            }
            ForEach ( $port in $ports ) {
                Write-Host ("FTS Server - Check port: $port" )
                $portListening = (Test-Connection -TargetName $FTSS -TCPPort $port -TimeoutSeconds 100)
                $portListening | Should -Be $true
            }
        }
    }

    Context 'Cleanup' {
        It "Cleanup of deployment" {
            Remove-AzResourceGroup -Name $testsResourceGroupName -Force
        }
    }
}
