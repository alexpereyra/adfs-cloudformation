param(
	[string]
    $AWSAccountNumber,

  [string]
    $AppstreamStackName

)


$AccountNumber = New-Object -TypeName psobject
$AccountNumber | Add-Member -MemberType NoteProperty -name "awsAccount" -Value "$AWSAccountNumber"

function AddRelyingParty
(
[string]$metadataURL = ("https://signin.aws.amazon.com/static/saml-metadata.xml"),
[string]$Name = ("appstream - newscycle - stack"),
[string]$SPIdentifier = ("https://signin.aws.amazon.com/saml")
)
{

Add-ADFSRelyingPartyTrust -Name $Name -MetadataUrl $metadataURL
Set-AdfsRelyingPartyTrust -TargetName $Name -Identifier $SPIdentifier

  $rules = @"

  @RuleName = "Name ID"
  c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType, Properties["http://schemas.xmlsoap.org/ws/2005/05/identity/claimproperties/format"] = "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent");

  @RuleName = "RoleSessionName"
  c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("https://aws.amazon.com/SAML/Attributes/RoleSessionName"), query = ";mail;{0}", param = c.Value);

  @RuleName = "Get Active Directory Groups"
  c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"] => add(store = "Active Directory", types = ("http://temp/variable"), query = ";tokenGroups;{0}", param = c.Value);

  @RuleName = "Roles"
  c:[Type == "http://temp/variable", Value =~ "(?i)^AWS-"]
 => issue(Type = "https://aws.amazon.com/SAML/Attributes/Role", Value = RegExReplace(c.Value, "AWS-$AWSAccountNumber-", "arn:aws:iam::$AWSAccountNumber`:saml-provider/$AppstreamStackName,arn:aws:iam::$AWSAccountNumber`:role/"));
"@
write-host $rules
Write-Verbose "Adding Claim Rules"
Set-ADFSRelyingPartyTrust -TargetName $Name -IssuanceTransformRules $rules

}

AddRelyingParty
