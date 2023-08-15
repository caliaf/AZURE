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

BeforeAll {
    $templateName = "Active-Active"
    $sourcePath = "$env:GITHUB_WORKSPACE\FortiProxy\$templateName"
    $scriptPath = "$env:GITHUB_WORKSPACE\FortiProxy\$templateName\test"
    $templateFileName = "azuredeploy.json"
    $templateFileLocation = "$sourcePath\$templateFileName"
    $templateParameterFileName = "azuredeploy.parameters.json"
    $templateParameterFileLocation = "$sourcePath\$templateParameterFileName"

    # Basic Variables
    $testsRandom = Get-Random 10001
    $testsPrefix = "FORTIQA"
    $testsResourceGroupName = "FORTIQA-$testsRandom-$templateName"
    $testsAdminUsername = "azureuser"
    $testsResourceGroupLocation = "westeurope"

    # ARM Template Variables
    $config = "config system global `n set gui-theme mariner `n end `n config system admin `n edit devops `n set accprofile super_admin `n set ssh-public-key1 `""
    $config += Get-Content $sshkeypub
    $config += "`" `n set password $testsResourceGroupName `n next `n end"
    $publicIP1Name = "$testsPrefix-FPX-PIP"
    $fortiProxyCount = 3
    $params = @{ 'adminUsername'=$testsAdminUsername
                 'adminPassword'=$testsResourceGroupName
                 'fortiProxyNamePrefix'=$testsPrefix
                 'fortiProxyAdditionalCustomData'=$config
                 'publicIP1Name'=$publicIP1Name
                 'fortiProxyCount'=$fortiProxyCount
               }
    $ports = @(40030, 50030, 40031, 50031, 40032, 50032)
}

Describe 'FPX A/A' {
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
            'outputs',
            'parameters',
            'resources',
            'variables'
            $templateProperties = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | % Name
            $templateProperties | Should -Be $expectedProperties
        }

        It 'Creates the expected Azure resources' {
            $expectedResources = 'Microsoft.Resources/deployments',
                                 'Microsoft.Compute/availabilitySets',
                                 'Microsoft.Network/virtualNetworks',
                                 'Microsoft.Network/networkSecurityGroups',
                                 'Microsoft.Network/publicIPAddresses',
                                 'Microsoft.Network/loadBalancers',
                                 'Microsoft.Network/loadBalancers/inboundNatRules',
                                 'Microsoft.Network/loadBalancers/inboundNatRules',
                                 'Microsoft.Network/loadBalancers',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Compute/virtualMachines'
            $templateResources = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Resources.type
            $templateResources | Should -Be $expectedResources
        }

        It 'Contains the expected parameters' {
            $expectedTemplateParameters = 'acceleratedNetworking',
                                          'adminPassword',
                                          'adminUsername',
                                          'availabilityOptions',
                                          'customImageReference',
                                          'externalLoadBalancer',
                                          'fortiManager',
                                          'fortiManagerIP',
                                          'fortiManagerSerial',
                                          'fortinetTags',
                                          'fortiProxyAdditionalCustomData',
                                          'fortiProxyCount',
                                          'fortiProxyImageSKU',
                                          'fortiProxyImageVersion',
                                          'fortiProxyLicenseBYOL1',
                                          'fortiProxyLicenseBYOL2',
                                          'fortiProxyLicenseBYOL3',
                                          'fortiProxyLicenseBYOL4',
                                          'fortiProxyLicenseBYOL5',
                                          'fortiProxyLicenseBYOL6',
                                          'fortiProxyLicenseBYOL7',
                                          'fortiProxyLicenseBYOL8',
                                          'fortiProxyNamePrefix',
                                          'instanceType',
                                          'location',
                                          'publicIP1Name',
                                          'publicIP1NewOrExisting',
                                          'publicIP1ResourceGroup',
                                          'serialConsole',
                                          'subnet1Name',
                                          'subnet1Prefix',
                                          'subnet1StartAddress',
                                          'subnet2Name',
                                          'subnet2Prefix',
                                          'subnet2StartAddress',
                                          'vnetAddressPrefix',
                                          'vnetName',
                                          'vnetNewOrExisting',
                                          'vnetResourceGroup'
            $templateParameters = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Parameters | Get-Member -MemberType NoteProperty | % Name | sort
            $templateParameters | Should -Be $expectedTemplateParameters
        }

    }

    Context 'Deployment' {

        It "Test deployment" {
            New-AzResourceGroup -Name $testsResourceGroupName -Location "$testsResourceGroupLocation"
            (Test-AzResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileLocation" -TemplateParameterObject $params).Count | Should -Not -BeGreaterThan 0
        }
        It "Deployment" {
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
            $fgt = (Get-AzPublicIpAddress -Name $publicIP1Name -ResourceGroupName $testsResourceGroupName).IpAddress
            Write-Host ("FortiProxy public IP: " + $fgt)
            $verify_commands = @'
            config system console
            set output standard
            end
            get system status
            show system interface
            show router static
            diag debug cloudinit show
            exit
'@
            $OFS = "`n"
        }
        It "FPX: Ports listening" {
            ForEach( $port in $ports ) {
                Write-Host ("Check port: $port" )
                $portListening = (Test-Connection -TargetName $fgt -TCPPort $port -TimeoutSeconds 100)
                $portListening | Should -Be $true
            }
        }
        It "FPX 1: Verify configuration" {
            $result = $verify_commands | ssh -p 50030 -tt -i $sshkey -o StrictHostKeyChecking=no devops@$fgt
            $LASTEXITCODE | Should -Be "0"
            Write-Host ("FPX CLI info: " + $result) -Separator `n
            $result | Should -Not -BeLike "*Command fail*"
        }
        It "FPX 2: Verify configuration" {
            $result = $verify_commands | ssh -p 50031 -tt -i $sshkey -o StrictHostKeyChecking=no devops@$fgt
            $LASTEXITCODE | Should -Be "0"
            Write-Host ("FPX CLI info: " + $result) -Separator `n
            $result | Should -Not -BeLike "*Command fail*"
        }
        It "FPX 3: Verify configuration" {
            $result = $verify_commands | ssh -p 50032 -tt -i $sshkey -o StrictHostKeyChecking=no devops@$fgt
            $LASTEXITCODE | Should -Be "0"
            Write-Host ("FPX CLI info: " + $result) -Separator `n
            $result | Should -Not -BeLike "*Command fail*"
        }
    }

    Context 'Cleanup' {
        It "Cleanup of deployment" {
            Remove-AzResourceGroup -Name $testsResourceGroupName -Force
        }
    }
}
