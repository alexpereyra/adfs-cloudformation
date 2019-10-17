param(
    [string]
    $DomainDNSName = "example.com",

    [string]
    $DomainNetBIOSName = "example",

    [string]
    $Username,

    [string]
    $Password,
	
	[string]
    $AWSAccountNumber,

    [string]
    $AppstreamStackName,
	
	[string]
    $FederationName,
	
	[string]
    $CertificateName,

    [switch]
    $FirstServer
)

try {
    Start-Transcript -Path C:\cfn\log\Install-ADFS.ps1.txt -Append

    $ErrorActionPreference = "Stop"

    $Pass = ConvertTo-SecureString $Password -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential -ArgumentList "$DomainNetBIOSName\$Username", $Pass

    if($FirstServer) {
        $FirstServerScriptBlock = {
            $ErrorActionPreference = "Stop"

        Import-PfxCertificate –FilePath "C:\cfn\scripts\$CertificateName.pfx" -CertStoreLocation cert:\localMachine\my -Password $Using:Pass
        $CertificateThumbprint = (dir Cert:\LocalMachine\My)[0].thumbprint

            function Get-ADDCs {
                [CmdletBinding()]
                param()
                $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()
                return @($domain.FindAllDiscoverableDomainControllers())
            }

            function Sync-ADDomain {
                [CmdletBinding()]
                param()
                $DCs = Get-ADDCs
                foreach ($DC in $DCs) {
                    foreach ($partition in $DC.Partitions) {
                        Write-Host "Forcing replication on $DC from all servers for partition $partition"
                        try {
                            $DC.SyncReplicaFromAllServers($partition, 'CrossSite')
                        }
                        catch {
                            Write-Host $_
                            $foreach.Reset()
                            continue
                        }
                    }
                }
            }

            }
            if ($CertificateAuthorities[0].Config) {
                $newCertReqParams.Add("OnlineCA",$CertificateAuthorities[0].Config)
            }

            Install-WindowsFeature ADFS-Federation -IncludeManagementTools
            $CertificateThumbprint = (dir Cert:\LocalMachine\My)[0].thumbprint
            Install-AdfsFarm -CertificateThumbprint $CertificateThumbprint -FederationServiceDisplayName ADFS -FederationServiceName $Using:FederationName -ServiceAccountCredential $Using:Credential -OverwriteConfiguration

            Install-WindowsFeature RSAT-DNS-Server
            $netip = Get-NetIPConfiguration
            $ipconfig = Get-NetIPAddress | ?{$_.IpAddress -eq $netip.IPv4Address.IpAddress}
            $dnsServers = @((Resolve-DnsName $Using:DomainDNSName -Type NS).NameHost)
            foreach ($dnsServer in $dnsServers) {
                $recordCreated = $false
                do {
                    try {
                        Add-DnsServerResourceRecordA -Name sts -ZoneName $Using:DomainDNSName -IPv4Address $ipconfig.IPAddress -Computername $dnsServer
                        Write-Host "DNS record created on DNS server $dnsServer"
                        $recordCreated = $true
                    }
                    catch {
                        Write-Host "Unable to create DNS record on DNS server $dnsServer. Retrying in 5 seconds."
                        Start-Sleep -Seconds 5
                    }
                } while (-not $recordCreated)
            }

            Sync-ADDomain -ErrorAction Continue
        }
        Invoke-Command -Authentication Credssp -Scriptblock $FirstServerScriptBlock -ComputerName $env:COMPUTERNAME -Credential $Credential
		$ADGroupName = "AWS-$AWSAccountNumber-$AppstreamStackName"
        $GroupDescription = "Newscycle appstream stack group"
        New-ADGroup -Name $ADGroupName -GroupCategory Security -GroupScope Global -Description $GroupDescription -Credential $Credential
    }
    else {
        $ServerScriptBlock = {
            $ErrorActionPreference = "Stop"

            Import-PfxCertificate –FilePath "\\ADFS1\cert\$CertificateName.pfx" -CertStoreLocation cert:\localMachine\my -Password $Using:Pass
            $CertificateThumbprint = (dir Cert:\LocalMachine\My)[0].thumbprint

            & setspn -s host/sts.$Using:DomainDNSName $Using:DomainNetBIOSName\$Using:Username

            while (-not (Resolve-DnsName -Name "adfs1.$Using:DomainDNSName" -ErrorAction SilentlyContinue)) { Write-Host "Unable to resolve adfs1.$Using:DomainDNSName. Waiting for 5 seconds before retrying."; Start-Sleep 5 }

            Install-WindowsFeature ADFS-Federation -IncludeManagementTools
            Add-AdfsFarmNode -CertificateThumbprint $CertificateThumbprint -ServiceAccountCredential $Using:Credential -PrimaryComputerName "adfs1.$Using:DomainDNSName" -PrimaryComputerPort 80 -OverwriteConfiguration
        }
        Invoke-Command -Authentication Credssp -Scriptblock $ServerScriptBlock -ComputerName $env:COMPUTERNAME -Credential $Credential
    }
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
    $_ | Write-AWSQuickStartException
}