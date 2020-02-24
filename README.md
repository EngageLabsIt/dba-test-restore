# DBA Test Restore

This solution is based on a single `.ps1` file and it allows to test a set of database backups via restore script in SQL Server. Any contribution on this will be really appreciated, since the implementation is at the start.

## How it works

The PowerShell script iterates through a folder which contains a set of `.bak` file. It doesn't restore log backups; instead, each backup is restored and, in case of any error, an optional email could be sent to a dedicated email address. You can configure the sender and the format of the subject and body strings. You can also set the behaviours for sending emails only when an exception is raised. Additionally, the solution creates automatically a log file (by the day of the execution) and appends log lines only when that file already exists.

## Prerequisites

This solution uses the `SqlServer` module and the script will install it when needed. Since it has been tested with BackupExec tool, a particular path has been used as the foundation of the script itself. The path where the PowerShell will iterate on is the following:

```txt
Drive (ex. D:\)
  - ServerName1 (ex. SQLPROD01)
    - InstanceName1 (ex. INST00)
      - DatabaseName1
        - backup_datetime.bak
      - DatabaseName2
        - backup_datetime.bak
      - DatabaseName3
        - backup_datetime.bak
  - ServerName2 (ex. SQLPROD02)
    - InstanceName2 (ex. MSSQSERVER - default is provided always)
      - DatabaseName1
        - backup_datetime.bak
      - DatabaseName2
        - backup_datetime.bak
```

Using this hierarchy is **mandatory**. This is because is the structure which the script needs when iterating. However, you can change the script structure and the final loop (for the databases) will work anyways.

## Json configuration file

The file `test-databasebackup.json` holds the configurations for the script. Here is a quick documentation of all the properties:

| property name | property description | value specifications | parent object |
| ------------- | -------------------- | ----- | ------------- |
| emailConfiguration | configurations for the email | root object (see properties below) | |
| emailTo | To: | a valid email address | emailConfiguration |
| emailOKSubject | subject for successful messages | string with two params, server name and database name | emailConfiguration |
| emailOKBody | body for successful messages | string with three params, database name, backup file and elapsed time | emailConfiguration |
| emailKOSubject | subject for error messages | string with two params, server name and database name | emailConfiguration |
| emailKOBody | body for error messages | string with three params, database name, backup file and error message | emailConfiguration |
| emailSmtp | smtp server | your smtp address | emailConfiguration |
| emailPort | port | port for your smtp server | emailConfiguration |
| emailPriority | priority | `"High"`, `"Low"`, `"Normal"`  | emailConfiguration |
| emailFrom | sender | suggested: a noreply address | emailConfiguration |
| username | smtp username | credential for smtp server | emailConfiguration |
| password | smtp password | credential for smtp server | emailConfiguration |
| sqlServerConfiguration | configurations for sql server | root object (see properties below) | |
| sqlServerInstanceName | name of the SQL Server instance | `SERVERNAME[\INSTANCENAME][,port]` | sqlServerConfiguration |
| sqlRestoreTemplates | array of templates | array (see elements below) | sqlServerConfiguration |
| databases | array of database names | list of strings which represent databases (`"DB1"`, `"DB2"`, ...) | sqlRestoreTemplates |
| template | RESTORE DATABASE command | T-SQL based languages with three params, database name, backup file and restore path | sqlRestoreTemplates |
| foldersConfiguration | configurations for file system | root object (see properties below) | |
| servers | array of objects | array (see elements below) | foldersConfiguration |
| name | name of the server | string for `SERVERNAME` only | servers |
| folderName | name of the folder where to find backups | string for `INSTANCENAME` (default MSSQLSERVER) | servers |
| drive | source drive | the source disk (ex. `D:\`) to read backups from | foldersConfiguration |
| defaultRestoreFolderName | target folder for restored databases | a path for target (ex. `X:\RestoredDatabases\`) | foldersConfiguration |
| behaviors | configurations for the script behaviors | root object (see properties below) | |
| sendEmail | specifies if you would like to send emails | bool, `false` by configuration | behaviors |
| onlySendEmailForFailedTasks | send email only when any error occurs | bool, `false` by configuration | behaviors |
| databasesToSkip | array of databases to skip | list of string (ex. `["master", "tempdb"]`) | behaviors |

## How to execute the script

You can execute the script using both PowerShell and a `.bat` file, which you can find in the repository. You can also use the SQL Server Agent Powershell job step. The user which is executing the script must get the right permission for the folders configured into the `.json` configuration file. For example, if you are executing the script via SQL Server Agent, be sure that the Agent user (better a proxy user) can read, write and modify files into the folders (source and destination).

Here are some example for calling it:

### executing from a BAT file

```vim
@powershell -NoProfile -ExecutionPolicy unrestricted -Command ".\test-databasebackup.ps1"
```

### executing within the script

```powershell
# Full mode
Restore-Databases -ConfigurationPath $PSScriptRoot\test-databasebackup.json
```

```powershell
# Quiet mode (logs will be written anyways)
Restore-Databases -ConfigurationPath $PSScriptRoot\test-databasebackup.json -Quiet
```

```powershell
# What-if mode (no logs and changes will be made, and no `Invoke-SqlCmd` will be executed)
Restore-Databases -ConfigurationPath $PSScriptRoot\test-databasebackup.json -WhatIf
```
