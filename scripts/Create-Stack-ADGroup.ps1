$ADGroupName = "AWS-012345678910-ExampleStack-ps"
$AWSAccount =
$GroupDescription = "Newscycle appstream stack group"

New-ADGroup -Name $ADGroupName -GroupCategory Security -GroupScope Global -Description $GroupDescription
