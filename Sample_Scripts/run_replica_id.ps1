param(
    $instance = 378
)

#--- user settings ------
#ueb from where to restore backups
$ueb = "rc02"
$user = "root"
$pass = "password"
#hyperv client to restore to replicas
$client_id=43
$replica_name_prefix="ueb02"
$restore_path="C:/vmtest/replica/"
$switch_name="test-vswitch"
#--- end of user settings ------




# main code, dont modify

$ErrorActionPreference = 'Stop'

if (!(Test-Path "$restore_path/logs" -PathType Container)) {
    New-Item -ItemType Directory -Force -Path "$restore_path/logs"
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information'
    )

    $date = (Get-Date -f g)
    $log = $restore_path + "logs/" + $instance
    "$date - [$severity] - $Message" | Out-File -Append -FilePath $log    
}

trap [Exception] {
      Write-Log -Severity Error -Message $("TRAPPED: " + $_.Exception.GetType().FullName);
      Write-Log -Severity Error -Message $("TRAPPED: " + $_.Exception.Message);
	  Write-Log -Severity Error -Message "ERROR:"
	  Write-Log -Severity Error -Message $_.InvocationInfo.PositionMessage
	  Write-Log -Severity Error -Message "ExitCode: 9"
      exit 9
}	


Import-Module Unitrends
Connect-UebServer -Server $ueb -User $user -Password $pass

$catalog = Get-UebCatalog -InstanceId $instance
$backup_date = [datetime]::Parse($catalog.last_backup_date).ToString("yyyyMMdd_HHmmss")
$backup_id = $catalog.last_backup_id
$vm_name = $replica_name_prefix + "_" + $catalog.asset + "_" + $backup_date
$directory = $restore_path + $vm_name

$vm = Get-VM|where-object {$_.name -eq $vm_name}
if($vm)
{
    Write-Progress -Id $instance -Activity $instance -Status "VM ($vm_name) already exists with backup_id $backup_id"  -PercentComplete 100 -completed
    sleep 5
    exit 0
}

# if restore folder exists but VM no, delete folder
if (Test-Path $directory -PathType Container) {
    Remove-Item -Path $directory -Recurse -Force
}

Write-Progress -Id $instance -Activity $instance -Status "Restoring backup_id $backup_id to $directory"  -PercentComplete 0 -completed

$restore = Start-UebRestoreFile -backupID $catalog.last_backup_id -clientID $client_id -directory $directory -flat $true
$restore_id = $restore.id

$restore_job = $null
while($restore_job -eq $null) {
    $restore_job = get-uebjob -Active|Where-Object {$_.id -eq $restore_id}
    Sleep 3
}

while($restore_job.status -eq "Queued" -or $restore_job.status -eq "Active" -or $restore_job.status -eq "Connecting")
{
    Write-Progress -Id $instance -Activity $instance -Status "Restoring backup_id $backup_id to $directory"  -PercentComplete $restore_job.percent_complete
    $restore_job = get-uebjob -Active|Where-Object {$_.id -eq $restore_id}
    Sleep 3
}

Write-Progress  -Id $instance -Activity $instance -Status "Restoring backup_id $backup_id to $directory"  -PercentComplete 100 -completed

# restore complete,change vm id, remove saved state, change disk path and register vm or other import incompatibilities
Write-Progress  -Id $instance -Activity $instance -Status "Import VM as $vm_name"  -PercentComplete 100 -completed
$new_xml = [guid]::NewGuid().ToString().ToUpper() + ".xml"

$xml = Get-Item -Path "$directory\*.xml"

Rename-Item -Path $xml -NewName $new_xml

$xml = Get-Item -Path "$directory\*.xml"

$report = Compare-VM  -Path $xml -Register
$report.VM|Remove-VMSavedState -ErrorAction Ignore
$report.VM|rename-vm -NewName $vm_name
$report.VM|Get-VMNetworkAdapter | Connect-VMNetworkAdapter -SwitchName $switch_name

# wait 3 secs to saved state to be removed
Sleep 3

# set harddisk location to restored folder
$vhds = $report.VM | Get-VMHardDiskDrive
foreach($vhd in $vhds)
{
    $path = $vhd.Path
    $vhd_name = $path.Substring($path.LastIndexOf("\"))
    
    $new_path = $directory + $vhd_name
    Write-Host $new_path
    Set-VMHardDiskDrive -VMHardDiskDrive $vhd -Path $new_path #–ControllerType $vhd.ControllerType –ControllerNumber $vhd.ControllerNumber -ControllerLocation $vhd.ControllerLocation
}

Import-VM $report

Remove-Item -Path "$directory\*.xml"
Remove-Item -Path "$directory\*.bin"
Remove-Item -Path "$directory\*.vsv"
Remove-Item -Path "$directory\*.##meta##"



# remove previous restores
$vm_prefix = $replica_name_prefix + "_" + $catalog.asset + "_*"
$vms = get-vm -name $vm_prefix|Sort-Object -Descending|Select-Object -Skip 1

foreach ($vm in $vms)
{
    Remove-VM -VM $vm -Force
    $remove_dir = $restore_path + $vm.name
    Remove-Item -Path $remove_dir -Recurse -Force
}

#remove orphaned folders
$folder_path = $restore_path + $vm_prefix 
$folders = Get-Item $folder_path|Sort-Object -Descending -Property name|Select-Object -Skip 1
foreach ($folder in $folders)
{
    Remove-Item -Path $folder -Recurse -Force
}