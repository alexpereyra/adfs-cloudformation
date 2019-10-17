#Export MetaData XML
$mUrl = (Get-ADFSEndpoint | where Protocol -eq "Federation Metadata").FullUrl.ToString()
$httpHelper = new-object System.Net.WebClient
$metadataAsString = $httpHelper.DownloadString($mUrl)
$httpHelper.DownloadFile($mUrl , "C:\cfn\scripts\metadata.xml")
