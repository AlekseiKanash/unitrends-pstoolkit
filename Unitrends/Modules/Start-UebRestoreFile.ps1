<#
.Synopsis
   Submits a File Restore Job
.DESCRIPTION
    Start-UebRestoreJob -backupID 11017 -clientID 35 -includes "c:/users/Administrator/" -directory "c:/recover"
.PARAMETER SID
    System ID of the Unitrends Appliance.
.PARAMETER BackupID
    Backup ID to be restored   
.PARAMETER ClientID
    ID of the Client Machine
.PARAMETER Directory
    Location on the server to re-direct this restore to. If blank, restore will go to where it was backed up from.
.PARAMETER Includes
    List of file paths to include into the restore
.PARAMETER Excludes
    List of file paths to exclude from the restore
.PARAMETER Flat
    Sets the job to restore without folder structure. Defaults to False. 
.EXAMPLE
    Start-UebRestoreFile -backupID 11017 -clientID 35 -includes "c:/users/Administrator/" -directory "c:/recover"
#>
function Start-UebRestoreFile{
param(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [int]$sid = 1,
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [int]$backupID,
    [int]$clientID,
    [string]$directory,
    [string[]]$includes,
    [string[]]$excludes,
    [bool]$flat = $false,
    [bool]$synthesis = $false
)
# Verb Options?   Start- Submit-




#region RestoreObject
# Build the Restore Object, make $target, $theseIncludes, $theseExcludes, then make $body out of all and more
# Build Target
$target = @{
    flat = $flat #Required
    non_destructive = $false #Required
    newer = $true #Required
    today = $false #Required
    unix = $false #Required
    directory = $directory #Optional, but including with blank works as not existing
}

#Build Include(s) and Exclude(s)
[array]$theseIncludes = $includes #Required, but may be empty
[array]$theseExcludes = $excludes #Required, but may be empty

#Build Body
$body = @{
    backup_id = $backupID #Required
    client_id = $clientID #Required
    target = $target #Optional
    before_cmd = "" #Required, but may be empty
    after_cmd = "" #Required, but may be empty
    synthesis = $synthesis #Required if synthesized files ?
    includes = $theseIncludes
    excludes = $theseExcludes
}
#endregion RestoreObject

UebPost "/api/restore/full/?sid=$sid" $body

}
