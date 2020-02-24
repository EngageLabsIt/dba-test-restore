function Write-Log
{
    [cmdletbinding(SupportsShouldProcess=$True)]
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Error","Warn","Info","Log")]
        [string]$Level="Log",

        [Parameter(Mandatory=$false)]
        [switch][bool]$NoNewLine=$false,

        [Parameter(Mandatory=$false)]
        [switch][bool]$Quiet=$false,

        [Parameter(Mandatory=$false)]
        [string]$ForegroundColor = "Gray"
    )

    Begin
    {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'

        if ($null -eq $ForegroundColor -or $ForegroundColor -eq "")
        {
            $ForegroundColor = "Gray"
        }
    }
    
    Process 
    {
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $FormattedShortDate = Get-Date -Format "yyyy-MM-dd"
        $logPath = Join-Path $PSScriptRoot "log_$FormattedShortDate.log"

        switch ($Level) 
        {
            "Error"
                {
                    Write-Error $Message
                    $LevelText = "ERROR:"
                }
            "Warn"
                {
                    Write-Warning $Message
                    $LevelText = "WARNING:"
                }
            "Info"
                {
                    Write-Verbose $Message
                    $LevelText = "INFO:"
                }
            "Log"
                {
                    if (!$Quiet)
                    {
                        Write-Host "$FormattedDate - $LevelText $Message" -ForegroundColor:$ForegroundColor
                    }
                }
            }

        "$FormattedDate $LevelText $Message" | Out-File -FilePath $logPath -Append
    }
    End 
    {

    }
}
function Get-SettingsFromJson
{
    param 
    (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    $settings = Get-Content -Path $FilePath | ConvertFrom-Json
    return $settings
}

function Get-RestoreScript
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$DatabaseName,

        [Parameter(Mandatory=$true)]
        [string]$BackupFileName,

        [Parameter(Mandatory=$true)]
        [string]$DefaultRestoreFolderName,

        [Parameter(Mandatory=$true)]
        [string]$SqlServerInstanceName,
        
        [Parameter(Mandatory=$true)]
        $ScriptConfiguration

    )
    $script = $ScriptConfiguration | Where-Object { $_.databases -contains $DatabaseName }
    $query = $script.Template -f $DatabaseName, $BackupFileName, $DefaultRestoreFolderName

    return $query
}

function Restore-Databases
{
    [cmdletbinding(SupportsShouldProcess=$True)]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$ConfigurationPath,

        [switch][bool]$Quiet
    )

    Begin
    {
        if (!(Get-Module -ListAvailable -Name "SqlServer")) {
            Write-Log -Level "Log" -Message "Installing SqlServer module..." -Quiet:$Quiet
            Install-Module -Name SqlServer -AllowClobber
        }
        Write-Host

        $Configuration = Get-SettingsFromJson -FilePath $ConfigurationPath

        # email configuration
        $objectProperty = [hashtable]@{
            emailTo = $Configuration.emailConfiguration.emailTo
            emailOKSubject = $Configuration.emailConfiguration.emailOKSubject
            emailOKBody = $Configuration.emailConfiguration.emailOKBody
            emailKOSubject = $Configuration.emailConfiguration.emailKOSubject
            emailKOBody = $Configuration.emailConfiguration.emailKOBody
            emailSmtp = $Configuration.emailConfiguration.emailSmtp
            emailPort = $Configuration.emailConfiguration.emailPort
            emailPriority = $Configuration.emailConfiguration.emailPriority
            emailFrom = $Configuration.emailConfiguration.emailFrom
            username = $Configuration.emailConfiguration.username
            password = $Configuration.emailConfiguration.password
        }
        $emailConfiguration = New-Object -TypeName psobject -Property $objectProperty

        # sql server configuration
        $objectProperty = [hashtable]@{
            sqlRestoreTemplates = $Configuration.sqlServerConfiguration.sqlRestoreTemplates
            sqlServerInstanceName = $Configuration.sqlServerConfiguration.sqlServerInstanceName
        }
        $sqlServerConfiguration = New-Object -TypeName psobject -Property $objectProperty

        # folder configuration
        $objectProperty = [hashtable]@{
            servers = $Configuration.foldersConfiguration.servers
            drive = $Configuration.foldersConfiguration.drive
            defaultRestoreFolderName = $Configuration.foldersConfiguration.defaultRestoreFolderName
        }
        $foldersConfiguration = New-Object -TypeName psobject -Property $objectProperty

        # behaviors
        $objectProperty = [hashtable]@{
            onlySendEmailForFailedTasks = $Configuration.behaviors.onlySendEmailForFailedTasks
            databasesToSkip = $Configuration.behaviors.databasesToSkip
            sendEmail = $Configuration.behaviors.sendEmail
        }
        $behaviors = New-Object -TypeName psobject -Property $objectProperty

        $password = ConvertTo-SecureString $emailConfiguration.password -AsPlainText -Force
        $emailCredentials = New-Object System.Management.Automation.PSCredential ($emailConfiguration.username, $password)
    }
    Process
    {
        Write-Log -Level "Log" -Message "=============================================================" -ForegroundColor "White" -Quiet:$Quiet
        Write-Log -Level "Log" -Message "Restoring and testing databases..." -ForegroundColor "White" -Quiet:$Quiet
        Write-Log -Level "Log" -Message " " -ForegroundColor "White" -Quiet:$Quiet
        
        foreach ($server in $foldersConfiguration.servers) {
            
            Write-Log -Level "Log" -Message "Database Server: ""$($server.name)""" -ForegroundColor "White" -Quiet:$Quiet

            $currentDatabaseFolder = Join-Path (Join-Path $foldersConfiguration.drive $server.name) $server.folderName

            if (Test-Path $currentDatabaseFolder)
            {
                $files = Get-ChildItem -Path $currentDatabaseFolder -Filter "*.bak" -Depth 2
                Write-Log -Level "Log" -Message "Found $($files.count) database backups in $currentDatabaseFolder." -Quiet:$Quiet
                foreach ($file in $files)
                {
                    try 
                    {
                        $database = Split-Path (Split-Path $file.FullName -Parent) -Leaf
        
                        if ($behaviors.databasesToSkip -notcontains $database)
                        {
                            $script = Get-RestoreScript -DatabaseName $database `
                                                        -SqlServerInstanceName $sqlServerConfiguration.sqlServerInstanceName`
                                                        -BackupFileName $file.FullName `
                                                        -DefaultRestoreFolderName $foldersConfiguration.defaultRestoreFolderName `
                                                        -ScriptConfiguration $sqlServerConfiguration.sqlRestoreTemplates
        
                            # restore
                            $startTime = Get-Date
                            if (!$WhatIfPreference.IsPresent)
                            { 
                                Write-Log -Level "Log" -Message "  Restoring database ""$database"" with file ""$($file.FullName)""..." -Quiet:$Quiet
                                Invoke-Sqlcmd -ServerInstance $sqlServerConfiguration.sqlServerInstanceName `
                                              -Database "master" `
                                              -Query $script `
                                              -ErrorAction 'Stop' `
                                              -QueryTimeout 0
                                Write-Log -Level "Log" -Message "  Done!" -ForegroundColor "Green" -Quiet:$Quiet
                            }     
                            else
                            {
                                Write-Host "What if: Performing the operation ""Restore"" on target ""$database""."
                            }
                            $elapsedTime = $(Get-Date) - $startTime
        
                            try 
                            {
                                # file removal
                                Write-Log -Level "Log" -Message "  Removing backup file $($file.FullName)..." -Quiet:$Quiet
                                Remove-Item $file.FullName
                                Write-Log -Level "Log" -Message "  Done!" -ForegroundColor "Green" -Quiet:$Quiet
                                
                                if (!$behaviors.onlySendEmailForFailedTasks)
                                {
                                    if ($behaviors.sendEmail)
                                    {
                                        $body = $emailConfiguration.emailOKBody -f $database, $($foldersConfiguration.backupFolderName), $($elapsedTime.TotalSeconds)
                                        $subject = $emailConfiguration.emailOKSubject -f $database, $server.name
                                        Send-MailMessage -From $emailConfiguration.emailFrom `
                                                        -To $emailConfiguration.emailTo `
                                                        -Subject $subject `
                                                        -Body $body `
                                                        -SmtpServer $emailConfiguration.emailSmtp `
                                                        -Port $emailConfiguration.emailPort `
                                                        -BodyAsHtml `
                                                        -Priority $emailConfiguration.emailPriority `
                                                        -Credential $emailCredentials
                                    
                                        Write-Log -Level "Warn" -Message "    An email with detail has been sent to slack $($emailConfiguration.emailTo)." -Quiet:$Quiet
                                    }
                                }   
                            }
                            catch {
                                Write-Log -Level "Error" -Message "Error moving file - $($error[0])" -Quiet:$Quiet
                                
                                if ($behaviors.sendEmail)
                                {
                                    Write-Log -Level "Error" -Message "Sending email to slack channel $($emailConfiguration.emailTo).)" -Quiet:$Quiet
        
                                    $body = "Error moving file {0} (database: {1}) - {2}}" -f $($file.FullName), $database, $error[0]
                                    $subject = $emailConfiguration.emailKOSubject -f $database, $server.name
                                    Send-MailMessage -From $emailConfiguration.emailFrom `
                                                    -To $emailConfiguration.emailTo `
                                                    -Subject subject `
                                                    -Body $body `
                                                    -SmtpServer $emailConfiguration.emailSmtp `
                                                    -Port $emailConfiguration.emailPort `
                                                    -BodyAsHtml `
                                                    -Priority $emailConfiguration.emailPriority `
                                                    -Credential $emailCredentials
                                }
                            }
                        }
                        else
                        {
                            Write-Log -Level "Warn" -Message "Skipping database $database (check the <databasesToSkip> property in the config file)."
                        }
                    } 
                    catch
                    {
                        Write-Log -Level "Error" -Message "Error during database backup ($database) file - $($error[0])"
                        
                        if ($behaviors.sendEmail)
                        {
                            Write-Log -Level "Info" -Message "Sending email to slack channel $($emailConfiguration.emailTo).)" -Quiet:$Quiet
        
                            $body = $emailConfiguration.emailKOBody -f $database, $($file.FullName), $error[0]
                            $subject = $emailConfiguration.emailKOSubject -f $database, $server.name
                            Send-MailMessage -From $emailConfiguration.emailFrom `
                                                -To $emailConfiguration.emailTo `
                                                -Subject subject `
                                                -Body $body `
                                                -SmtpServer $emailConfiguration.emailSmtp `
                                                -Port $emailConfiguration.emailPort `
                                                -BodyAsHtml `
                                                -Priority $emailConfiguration.emailPriority `
                                                -Credential $emailCredentials
                        }
                    }
                }
            } 
            else 
            {
                Write-Log -Level "Warn" -Message "Skipping folder $currentDatabaseFolder (does not exist)." -Quiet:$Quiet
            }
        }
        Write-Log -Level "Log" -Message " " -ForegroundColor "White" -Quiet:$Quiet
        Write-Log -Level "Log" -Message "Execution completed." -ForegroundColor "White" -Quiet:$Quiet
        Write-Log -Level "Log" -Message "=============================================================" -ForegroundColor "White" -Quiet:$Quiet
    }
    End
    {

    }
}

Restore-Databases -ConfigurationPath $PSScriptRoot\test-databasebackup.json #-WhatIf -Quiet