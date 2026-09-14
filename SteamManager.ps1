<#
.SYNOPSIS
    Steam Manager V1

.DESCRIPTION
    Manages Steam dedicated server instances for AppID 4785920.
    Includes first-run setup, config wizard, SteamCMD auto-detection,
    instance deployment, updates, startup, shutdown, status checks,
    and interactive help.

.NOTES
    File Name: SteamManager.ps1
    Author:  CTFRuNnEr
    Version: 1.0
    AppID:   4785920
#>

[CmdletBinding()]
param(
    [string]$Command = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppId = 4785920
$script:ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:ScriptDirectory 'config.json'
$script:BaseRoot = 'C:\GameServers'
$script:DefaultStartupTemplate = '-log -port={PORT} -QueryPort={QUERYPORT}'

function Write-StatusLog {
    <#
    .SYNOPSIS
        Writes informational status updates.
    .PARAMETER Message
        Message text to display.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message" -ForegroundColor Cyan
}

function Show-HelpMenu {
    <#
    .SYNOPSIS
        Displays the top-level help menu.
    #>
    Write-Host "" 
    Write-Host 'Steam Manager V1 Help' -ForegroundColor Yellow
    Write-Host '---------------------' -ForegroundColor Yellow
    Write-Host 'Commands:'
    Write-Host '  Deploy          - Create a new server instance'
    Write-Host '  Update          - Update an instance using SteamCMD'
    Write-Host '  Start           - Start a server instance'
    Write-Host '  Stop            - Stop a running server instance'
    Write-Host '  Status          - Show server status for all or one instance'
    Write-Host '  Configuration   - View or edit configuration'
    Write-Host '  Help            - Display help'
    Write-Host '  Exit            - Close the menu'
    Write-Host ''
    Write-Host 'Inline prompt help:'
    Write-Host '  ?         - show the main menu help'
    Write-Host '  ?1        - setup wizard help'
    Write-Host '  ?2        - deployment help'
    Write-Host '  ?3        - startup help'
    Write-Host '  ?4        - status help'
    Write-Host '  ?5        - configuration help'
    Write-Host '  ?6        - deployment port assignment help'
    Write-Host '  ?7        - executable detection help'
    Write-Host ''
}

function Show-HelpById {
    <#
    .SYNOPSIS
        Displays a specific help topic.
    .PARAMETER HelpId
        Numeric help ID.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$HelpId
    )

    switch ($HelpId) {
        1 {
            Write-Host 'Setup Wizard Help:' -ForegroundColor Yellow
            Write-Host '  - First-run setup creates config.json.'
            Write-Host '  - SteamCMD auto-detects the steamcmd.exe path.'
            Write-Host '  - The script shows a summary before saving.'
            Write-Host '  - Example: C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe'
        }
        2 {
            Write-Host 'Deployment Help:' -ForegroundColor Yellow
            Write-Host '  - Uses anonymous SteamCMD login.'
            Write-Host '  - Downloads AppID 4785920.'
            Write-Host '  - Creates directories such as C:\GameServers\Server001.'
            Write-Host '  - Example: +force_install_dir "C:\GameServers\Server001" +login anonymous +app_update 4785920 validate +quit'
        }
        3 {
            Write-Host 'Startup Help:' -ForegroundColor Yellow
            Write-Host '  - Startup arguments use the template: -log -port={PORT} -QueryPort={QUERYPORT}'
            Write-Host '  - Available variables: {PORT}, {QUERYPORT}, {NAME}'
            Write-Host '  - Example: -log -port=7777 -QueryPort=27015'
        }
        4 {
            Write-Host 'Status Help:' -ForegroundColor Yellow
            Write-Host '  - Shows State, PID, Port, QueryPort, Crash Count, and Log Age.'
            Write-Host '  - States: Healthy, Running, Stopped, Crashed.'
            Write-Host '  - Uses the instance log to estimate freshness.'
        }
        5 {
            Write-Host 'Configuration Help:' -ForegroundColor Yellow
            Write-Host '  - Stores settings in config.json in the script directory.'
            Write-Host '  - Edit the SteamCMD path, game root, and AppID when needed.'
            Write-Host '  - Example: C:\GameServers'
        }
        6 {
            Write-Host 'Port Assignment Help:' -ForegroundColor Yellow
            Write-Host '  - Server001 = Port 7777 / QueryPort 27015'
            Write-Host '  - Server002 = Port 7778 / QueryPort 27016'
            Write-Host '  - Each server increments by 1 port and 1 query port.'
        }
        7 {
            Write-Host 'Executable Detection Help:' -ForegroundColor Yellow
            Write-Host '  - The script scans for .exe files in an instance.'
            Write-Host '  - It ignores Editor, Launcher, and CrashReport executables.'
            Write-Host '  - If the binary is missing, it rescans and repairs the path.'
        }
        default {
            Show-HelpMenu
        }
    }
}

function Get-CommonSteamCmdCandidates {
    <#
    .SYNOPSIS
        Returns common candidate paths where steamcmd.exe may be installed.
    .OUTPUTS
        System.String[]
    #>
    $candidates = @()

    $knownRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        'C:\Program Files',
        'C:\Program Files (x86)',
        'D:\Program Files',
        'D:\Program Files (x86)',
        'C:\Steam',
        'D:\Steam',
        'C:\Games',
        'D:\Games'
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -Path $_ -PathType Container)
    } | Select-Object -Unique

    foreach ($root in $knownRoots) {
        $candidates += Join-Path $root 'Steam\steamcmd\steamcmd.exe'
        $candidates += Join-Path $root 'steamcmd\steamcmd.exe'
        $candidates += Join-Path $root 'SteamCMD\steamcmd.exe'
        $candidates += Join-Path $root 'steamcmd.exe'
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        if ($drive.Root -and (Test-Path $drive.Root)) {
            $candidates += Join-Path $drive.Root 'Steam\steamcmd\steamcmd.exe'
            $candidates += Join-Path $drive.Root 'steamcmd\steamcmd.exe'
            $candidates += Join-Path $drive.Root 'SteamCMD\steamcmd.exe'
        }
    }

    return $candidates | Select-Object -Unique
}

function AutoDetect-SteamCmdPath {
    <#
    .SYNOPSIS
        Auto-detects the SteamCMD executable path.
    .OUTPUTS
        System.String
    #>
    $candidates = Get-CommonSteamCmdCandidates

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Returns the default configuration values.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    $steamCmdPath = AutoDetect-SteamCmdPath

    return @{
        AppId = $script:AppId
        BaseRoot = $script:BaseRoot
        SteamCmdPath = $steamCmdPath
        StartupTemplate = $script:DefaultStartupTemplate
        DefaultPort = 7777
        DefaultQueryPort = 27015
        LastInstance = 0
    }
}

function Save-Config {
    <#
    .SYNOPSIS
        Saves a configuration object to config.json.
    .PARAMETER Config
        Configuration hashtable to persist.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $json = $Config | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

function Read-Config {
    <#
    .SYNOPSIS
        Reads config.json if it exists.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    if (-not (Test-Path $script:ConfigPath)) {
        return $null
    }

    $raw = Get-Content -Path $script:ConfigPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $config = $raw | ConvertFrom-Json
    if ($null -eq $config) {
        return $null
    }

    $result = @{}
    foreach ($property in $config.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

function Get-ConfigValueWithPrompt {
    <#
    .SYNOPSIS
        Prompts for a configuration value while supporting inline help.
    .PARAMETER Name
        Friendly configuration name.
    .PARAMETER Description
        Detailed description shown during prompt.
    .PARAMETER DefaultValue
        Default value to use when blank.
    .PARAMETER Example
        Example of valid input.
    .PARAMETER HelpId
        Numeric help topic ID.
    .OUTPUTS
        System.String
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$DefaultValue,
        [Parameter(Mandatory = $true)]
        [string]$Example,
        [Parameter(Mandatory = $true)]
        [int]$HelpId
    )

    while ($true) {
        $promptText = "$Name [$DefaultValue]`n$Description`nExample: $Example`n> "
        $value = Read-Host $promptText

        if ($value -eq '?') {
            Show-HelpMenu
            continue
        }

        if ($value -match '^\?(\d+)$') {
            Show-HelpById -HelpId ([int]$Matches[1])
            continue
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            return $DefaultValue
        }

        return $value.Trim()
    }
}

function Invoke-SetupWizard {
    <#
    .SYNOPSIS
        Runs the first-run setup wizard.
    #>
    Write-Host ''
    Write-Host 'Steam Manager Setup Wizard' -ForegroundColor Yellow
    Write-Host '=========================' -ForegroundColor Yellow

    $defaultConfig = Get-DefaultConfig

    $defaultSteamCmd = if ($null -eq $defaultConfig.SteamCmdPath) { 'C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe' } else { $defaultConfig.SteamCmdPath }
    $steamCmdPath = Get-ConfigValueWithPrompt -Name 'SteamCMD Path' -Description 'Location of steamcmd.exe' -DefaultValue $defaultSteamCmd -Example 'C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe' -HelpId 1
    $baseRoot = Get-ConfigValueWithPrompt -Name 'Server Root' -Description 'Root folder used for all server instances' -DefaultValue $defaultConfig.BaseRoot -Example 'C:\GameServers' -HelpId 5
    $appId = Get-ConfigValueWithPrompt -Name 'App ID' -Description 'SteamCMD AppID to install/update' -DefaultValue $defaultConfig.AppId -Example '4785920' -HelpId 2
    $startupTemplate = Get-ConfigValueWithPrompt -Name 'Startup Template' -Description 'Template for launch arguments' -DefaultValue $defaultConfig.StartupTemplate -Example '-log -port={PORT} -QueryPort={QUERYPORT}' -HelpId 3

    $config = @{
        AppId = $appId
        BaseRoot = $baseRoot
        SteamCmdPath = $steamCmdPath
        StartupTemplate = $startupTemplate
        DefaultPort = 7777
        DefaultQueryPort = 27015
        LastInstance = 0
    }

    Write-Host ''
    Write-Host 'Configuration Summary:' -ForegroundColor Yellow
    Write-Host "  SteamCMD Path   : $($config.SteamCmdPath)"
    Write-Host "  Server Root     : $($config.BaseRoot)"
    Write-Host "  App ID          : $($config.AppId)"
    Write-Host "  Startup Template: $($config.StartupTemplate)"

    $saveChoice = Read-Host 'Save configuration? (Y/N)'
    if ($saveChoice -notmatch '^(Y|YES)$') {
        Write-StatusLog 'Setup cancelled. Configuration was not saved.'
        return $null
    }

    $config | ConvertTo-Json | Set-Content -Path $script:ConfigPath -Encoding UTF8
    Write-StatusLog "Configuration saved to $script:ConfigPath"
    return $config
}

function Ensure-Config {
    <#
    .SYNOPSIS
        Ensures config.json exists and returns the current configuration.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    if (-not (Test-Path $script:ConfigPath)) {
        $config = Invoke-SetupWizard
        if ($null -eq $config) {
            throw 'Setup cancelled. A valid configuration is required.'
        }
        return $config
    }

    $config = Read-Config
    if ($null -eq $config) {
        $config = Invoke-SetupWizard
        if ($null -eq $config) {
            throw 'Unable to load configuration.'
        }
    }

    return $config
}

function Get-NextInstanceInfo {
    <#
    .SYNOPSIS
        Gets the next instance name, Port, and QueryPort using V1 numbering.
    .PARAMETER Config
        Active configuration.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $root = $Config.BaseRoot
    if (-not (Test-Path $root)) {
        New-Item -Path $root -ItemType Directory -Force | Out-Null
    }

    $existing = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Server\d{3}$' } | Select-Object -ExpandProperty Name
    $numbers = @()
    foreach ($item in $existing) {
        if ($item -match '^Server(\d{3})$') {
            $numbers += [int]$Matches[1]
        }
    }

    $nextNumber = 1
    if ($numbers.Count -gt 0) {
        $nextNumber = ($numbers | Sort-Object | Select-Object -Last 1) + 1
    }

    $instanceName = 'Server{0:D3}' -f $nextNumber
    $port = 7777 + ($nextNumber - 1)
    $queryPort = 27015 + ($nextNumber - 1)

    return @{
        Number = $nextNumber
        Name = $instanceName
        Port = $port
        QueryPort = $queryPort
        Path = Join-Path $root $instanceName
    }
}

function Test-IsExcludedServerExecutable {
    <#
    .SYNOPSIS
        Identifies executables that are not dedicated server binaries.
    .PARAMETER Path
        Executable path to inspect.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $name = Split-Path -Path $Path -Leaf
    return $name -match 'Editor|Launcher|CrashReport|Prereq|Redist|Installer|unins|steamcmd'
}

function Get-ServerExecutablePath {
    <#
    .SYNOPSIS
        Scans an instance directory for the server executable.
    .PARAMETER InstancePath
        Path of the server instance.
    .OUTPUTS
        System.String
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstancePath
    )

    if (-not (Test-Path $InstancePath)) {
        return $null
    }

    $candidates = Get-ChildItem -Path $InstancePath -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue
    if (-not $candidates) {
        return $null
    }

    $filtered = $candidates | Where-Object {
        -not (Test-IsExcludedServerExecutable -Path $_.FullName)
    }

    if (-not $filtered) {
        return $null
    }

    $best = $filtered | Sort-Object { $_.FullName.Length } -Descending | Select-Object -First 1
    return $best.FullName
}

function Repair-ExecutablePath {
    <#
    .SYNOPSIS
        Re-scans an instance and repairs the executable path in instance.json.
    .PARAMETER InstancePath
        Path of the server instance.
    .OUTPUTS
        System.String
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstancePath
    )

    $instanceFile = Join-Path $InstancePath 'instance.json'
    if (-not (Test-Path $instanceFile)) {
        return $null
    }

    $instanceData = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json
    $exe = Get-ServerExecutablePath -InstancePath $InstancePath
    if (-not $exe) {
        return $null
    }

    $instanceData.ExecutablePath = $exe
    $instanceData | ConvertTo-Json -Depth 10 | Set-Content -Path $instanceFile -Encoding UTF8
    return $exe
}

function New-InstanceJson {
    <#
    .SYNOPSIS
        Creates the instance metadata document.
    .PARAMETER InstanceName
        Name of the server instance.
    .PARAMETER InstancePath
        Directory path for the instance.
    .PARAMETER Port
        Game port.
    .PARAMETER QueryPort
        Query port.
    .PARAMETER ExecutablePath
        Resolved executable path.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [string]$InstancePath,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $true)]
        [int]$QueryPort,
        [string]$ExecutablePath = ''
    )

    $data = @{
        Name = $InstanceName
        AppId = $script:AppId
        Port = $Port
        QueryPort = $QueryPort
        ExecutablePath = $ExecutablePath
        StartupTemplate = $script:DefaultStartupTemplate
        State = 'Stopped'
        PID = 0
        CrashCount = 0
        LastStart = $null
        LastStop = $null
        LastUpdate = (Get-Date).ToString('o')
        Created = (Get-Date).ToString('o')
        LogPath = Join-Path $InstancePath 'server.log'
    }

    return $data
}

function Set-InstanceState {
    <#
    .SYNOPSIS
        Updates the persistent status information inside instance.json.
    .PARAMETER InstancePath
        Path of the server instance.
    .PARAMETER State
        State name.
    .PARAMETER ProcessId
        PID, if any.
    .PARAMETER CrashCount
        Crash count to store.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstancePath,
        [Parameter(Mandatory = $true)]
        [string]$State,
        [int]$ProcessId = 0,
        [int]$CrashCount = 0
    )

    $instanceFile = Join-Path $InstancePath 'instance.json'
    if (-not (Test-Path $instanceFile)) {
        return
    }

    $json = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json
    $json.State = $State
    $json.PID = $ProcessId
    $json.CrashCount = $CrashCount

    if ($State -eq 'Running') {
        $json.LastStart = (Get-Date).ToString('o')
    }
    elseif ($State -eq 'Stopped' -or $State -eq 'Crashed') {
        $json.LastStop = (Get-Date).ToString('o')
    }

    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $instanceFile -Encoding UTF8
}

function Get-InstanceByName {
    <#
    .SYNOPSIS
        Locates an instance by name.
    .PARAMETER instanceName
        Name of the instance, such as Server001.
    .OUTPUTS
        System.String
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$instanceName
    )

    $config = Ensure-Config
    $root = $config.BaseRoot
    $path = Join-Path $root $instanceName
    if (Test-Path $path) {
        return $path
    }

    return $null
}

function Invoke-SteamCmdUpdate {
    <#
    .SYNOPSIS
        Runs SteamCMD against an instance directory.
    .PARAMETER SteamCmdPath
        Full path to steamcmd.exe.
    .PARAMETER InstancePath
        Destination folder for the game files.
    .PARAMETER AppId
        Steam AppID to install or update.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SteamCmdPath,
        [Parameter(Mandatory = $true)]
        [string]$InstancePath,
        [Parameter(Mandatory = $true)]
        [int]$AppId
    )

    if (-not (Test-Path $SteamCmdPath)) {
        throw "SteamCMD executable not found: $SteamCmdPath"
    }

    $arguments = @(
        '+force_install_dir', $InstancePath,
        '+login', 'anonymous',
        '+app_update', $AppId,
        'validate',
        '+quit'
    )

    Write-StatusLog "Updating AppID $AppId in $InstancePath"
    & $SteamCmdPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD update failed with exit code $LASTEXITCODE"
    }
}

function Deploy-Instance {
    <#
    .SYNOPSIS
        Deploys a new server instance using SteamCMD.
    .PARAMETER Config
        Active configuration.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $next = Get-NextInstanceInfo -Config $Config
    $instancePath = $next.Path

    if (-not (Test-Path $instancePath)) {
        New-Item -Path $instancePath -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $Config.SteamCmdPath)) {
        $detected = AutoDetect-SteamCmdPath
        if ($detected) {
            $Config.SteamCmdPath = $detected
            Save-Config -Config $Config
        }
        else {
            throw 'Unable to locate steamcmd.exe. Please confirm the path in configuration.'
        }
    }

    Invoke-SteamCmdUpdate -SteamCmdPath $Config.SteamCmdPath -InstancePath $instancePath -AppId $Config.AppId

    $exePath = Get-ServerExecutablePath -InstancePath $instancePath
    if (-not $exePath) {
        throw "No valid server executable was found in $instancePath after deployment."
    }

    $instanceData = New-InstanceJson -InstanceName $next.Name -InstancePath $instancePath -Port $next.Port -QueryPort $next.QueryPort -ExecutablePath $exePath
    $instanceData | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $instancePath 'instance.json') -Encoding UTF8

    $batchFile = Join-Path $instancePath 'StartServer.bat'
    $startArguments = '"' + $exePath + '" ' + $Config.StartupTemplate.Replace('{PORT}', $next.Port).Replace('{QUERYPORT}', $next.QueryPort).Replace('{NAME}', $next.Name)
    @(
        '@echo off',
        'setlocal',
        "cd /d `"$instancePath`"",
        "call $startArguments"
    ) | Set-Content -Path $batchFile -Encoding ASCII

    $configFile = Join-Path $instancePath 'instance.json'
    Write-StatusLog "Deployed $($next.Name) at $instancePath"
    Write-StatusLog "Port $($next.Port) QueryPort $($next.QueryPort)"
    return $instanceData
}

function Update-Instance {
    <#
    .SYNOPSIS
        Updates a specific instance with the latest game files.
    .PARAMETER InstanceName
        Name of the target instance.
    .PARAMETER Config
        Active configuration.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $instancePath = Get-InstanceByName -instanceName $InstanceName
    if (-not $instancePath) {
        throw "Instance $InstanceName was not found."
    }

    $instanceFile = Join-Path $instancePath 'instance.json'
    if (-not (Test-Path $instanceFile)) {
        throw "Missing instance metadata for $InstanceName"
    }

    $instanceData = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json
    $exePath = $instanceData.ExecutablePath

    if (-not $exePath -or -not (Test-Path $exePath) -or (Test-IsExcludedServerExecutable -Path $exePath)) {
        $exePath = Repair-ExecutablePath -InstancePath $instancePath
        if (-not $exePath) {
            throw "Executable missing and could not be auto-detected in $instancePath"
        }
        $instanceData.ExecutablePath = $exePath
    }

    Invoke-SteamCmdUpdate -SteamCmdPath $Config.SteamCmdPath -InstancePath $instancePath -AppId $Config.AppId
    $instanceData.LastUpdate = (Get-Date).ToString('o')
    $instanceData | ConvertTo-Json -Depth 10 | Set-Content -Path $instanceFile -Encoding UTF8

    Write-StatusLog "Updated $InstanceName successfully."
    return $instanceData
}

function Get-ResolvedStartupArguments {
    <#
    .SYNOPSIS
        Builds startup arguments from the configured template.
    .PARAMETER InstanceData
        Instance metadata.
    .PARAMETER Template
        Startup template string.
    .OUTPUTS
        System.String
    #>
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$InstanceData,
        [Parameter(Mandatory = $true)]
        [string]$Template
    )

    $args = $Template
    $args = $args.Replace('{PORT}', [string]$InstanceData.Port)
    $args = $args.Replace('{QUERYPORT}', [string]$InstanceData.QueryPort)
    $args = $args.Replace('{NAME}', [string]$InstanceData.Name)
    return $args
}

function Start-Instance {
    <#
    .SYNOPSIS
        Starts an instance and stores its PID.
    .PARAMETER InstanceName
        Name of the instance to start.
    .PARAMETER Config
        Active configuration.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    $instancePath = Get-InstanceByName -instanceName $InstanceName
    if (-not $instancePath) {
        throw "Instance $InstanceName was not found."
    }

    $instanceFile = Join-Path $instancePath 'instance.json'
    $instanceData = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json

    $exePath = $instanceData.ExecutablePath
    if (-not $exePath -or -not (Test-Path $exePath) -or (Test-IsExcludedServerExecutable -Path $exePath)) {
        $exePath = Repair-ExecutablePath -InstancePath $instancePath
    }

    if (-not $exePath) {
        throw "No valid executable was found for instance $InstanceName."
    }

    $startupArgs = Get-ResolvedStartupArguments -InstanceData $instanceData -Template $Config.StartupTemplate
    $logPath = if ($instanceData.LogPath) { $instanceData.LogPath } else { Join-Path $instancePath 'server.log' }
    if (Test-Path $logPath) {
        Remove-Item -Path $logPath -Force
    }
    $startupArgs = ($startupArgs + ' -abslog="' + $logPath + '"').Trim()

    $process = Start-Process -FilePath $exePath -ArgumentList $startupArgs -WorkingDirectory $instancePath -PassThru -WindowStyle Normal

    Set-InstanceState -InstancePath $instancePath -State 'Running' -ProcessId $process.Id -CrashCount $instanceData.CrashCount

    $instanceData.State = 'Running'
    $instanceData.PID = $process.Id
    $instanceData.LastStart = (Get-Date).ToString('o')
    $instanceData | ConvertTo-Json -Depth 10 | Set-Content -Path $instanceFile -Encoding UTF8

    Write-StatusLog "Started $InstanceName (PID $($process.Id)). Log: $logPath"
    return $process
}

function Stop-Instance {
    <#
    .SYNOPSIS
        Stops a running instance by PID.
    .PARAMETER InstanceName
        Name of the instance to stop.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    $instancePath = Get-InstanceByName -instanceName $InstanceName
    if (-not $instancePath) {
        throw "Instance $InstanceName was not found."
    }

    $instanceFile = Join-Path $instancePath 'instance.json'
    $instanceData = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json
    $processId = [int]$instanceData.PID

    if ($processId -gt 0) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Id $processId -Force
            Write-StatusLog "Stopped $InstanceName (PID $processId)."
        }
    }

    Set-InstanceState -InstancePath $instancePath -State 'Stopped' -ProcessId 0 -CrashCount ([int]$instanceData.CrashCount)
    Write-StatusLog "Instance $InstanceName marked as stopped."
}

function Get-LogAgeMinutes {
    <#
    .SYNOPSIS
        Determines the age of the instance log in minutes.
    .PARAMETER LogPath
        Path to the log file.
    .OUTPUTS
        System.Double
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    if (-not (Test-Path $LogPath)) {
        return 9999
    }

    $lastWrite = (Get-Item $LogPath).LastWriteTime
    return ((Get-Date) - $lastWrite).TotalMinutes
}

function Get-InstanceStatus {
    <#
    .SYNOPSIS
        Returns status information for a specific instance.
    .PARAMETER InstanceName
        Name of the instance to inspect.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName
    )

    $instancePath = Get-InstanceByName -instanceName $InstanceName
    if (-not $instancePath) {
        throw "Instance $InstanceName was not found."
    }

    $instanceFile = Join-Path $instancePath 'instance.json'
    if (-not (Test-Path $instanceFile)) {
        throw "Missing instance metadata for $InstanceName"
    }

    $instanceData = Get-Content -Path $instanceFile -Raw | ConvertFrom-Json
    $processId = [int]$instanceData.PID
    $logAge = Get-LogAgeMinutes -LogPath $instanceData.LogPath
    $state = 'Stopped'

    if ($processId -gt 0) {
        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($proc) {
            if ([int]$instanceData.CrashCount -gt 0) {
                $state = 'Crashed'
            }
            elseif ($logAge -lt 30) {
                $state = 'Healthy'
            }
            else {
                $state = 'Running'
            }
        }
        else {
            $state = if ([int]$instanceData.CrashCount -gt 0) { 'Crashed' } else { 'Stopped' }
        }
    }
    else {
        $state = if ([int]$instanceData.CrashCount -gt 0) { 'Crashed' } else { 'Stopped' }
    }

    $instanceData.State = $state
    $instanceData | ConvertTo-Json -Depth 10 | Set-Content -Path $instanceFile -Encoding UTF8

    return @{
        Name = $instanceData.Name
        State = $state
        PID = $processId
        Port = [int]$instanceData.Port
        QueryPort = [int]$instanceData.QueryPort
        CrashCount = [int]$instanceData.CrashCount
        LogAge = [math]::Round($logAge, 2)
        LogPath = $instanceData.LogPath
    }
}

function Show-StatusForAll {
    <#
    .SYNOPSIS
        Shows status for all instances.
    #>
    $config = Ensure-Config
    $root = $config.BaseRoot
    if (-not (Test-Path $root)) {
        Write-Host "No server root found at $root" -ForegroundColor Yellow
        return
    }

    $instances = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Server\d{3}$' }
    if (-not $instances) {
        Write-Host 'No server instances found.' -ForegroundColor Yellow
        return
    }

    foreach ($instance in $instances) {
        try {
            $status = Get-InstanceStatus -InstanceName $instance.Name
            Write-Host ''
            Write-Host "Instance: $($status.Name)" -ForegroundColor Yellow
            Write-Host "  State      : $($status.State)"
            Write-Host "  PID        : $($status.PID)"
            Write-Host "  Port       : $($status.Port)"
            Write-Host "  QueryPort  : $($status.QueryPort)"
            Write-Host "  Crash Count: $($status.CrashCount)"
            Write-Host "  Log Age    : $($status.LogAge) minutes"
        }
        catch {
            Write-Host "Instance $($instance.Name) has no valid status data." -ForegroundColor DarkYellow
        }
    }
}

function Show-Configuration {
    <#
    .SYNOPSIS
        Displays the active configuration.
    #>
    $config = Ensure-Config
    Write-Host ''
    Write-Host 'Current Configuration' -ForegroundColor Yellow
    Write-Host '---------------------' -ForegroundColor Yellow
    foreach ($entry in $config.GetEnumerator() | Sort-Object Key) {
        Write-Host "  $($entry.Key): $($entry.Value)"
    }
}

function Invoke-ConfigurationEditor {
    <#
    .SYNOPSIS
        Lets the user update configuration values via interactive prompts.
    #>
    $config = Ensure-Config

    $config.SteamCmdPath = Get-ConfigValueWithPrompt -Name 'SteamCMD Path' -Description 'Location of steamcmd.exe' -DefaultValue $config.SteamCmdPath -Example 'C:\Program Files (x86)\Steam\steamcmd\steamcmd.exe' -HelpId 1
    $config.BaseRoot = Get-ConfigValueWithPrompt -Name 'Server Root' -Description 'Root folder used for all server instances' -DefaultValue $config.BaseRoot -Example 'C:\GameServers' -HelpId 5
    $config.AppId = Get-ConfigValueWithPrompt -Name 'App ID' -Description 'SteamCMD AppID to install/update' -DefaultValue $config.AppId -Example '4785920' -HelpId 2
    $config.StartupTemplate = Get-ConfigValueWithPrompt -Name 'Startup Template' -Description 'Template for launch arguments' -DefaultValue $config.StartupTemplate -Example '-log -port={PORT} -QueryPort={QUERYPORT}' -HelpId 3

    Save-Config -Config $config
    Write-StatusLog 'Configuration updated.'
    Show-Configuration
}

function Show-Menu {
    <#
    .SYNOPSIS
        Shows the interactive menu and processes commands.
    #>
    Show-HelpMenu

    while ($true) {
        $choice = Read-Host 'SteamManager> '
        if ([string]::IsNullOrWhiteSpace($choice)) {
            continue
        }

        $choice = $choice.Trim()

        if ($choice -match '^\?(\d+)$') {
            Show-HelpById -HelpId ([int]$Matches[1])
            continue
        }

        if ($choice -eq '?') {
            Show-HelpMenu
            continue
        }

        switch ($choice.ToLowerInvariant()) {
            'deploy' {
                $config = Ensure-Config
                Deploy-Instance -Config $config
            }
            'update' {
                $name = Read-Host 'Instance name (for example Server001)'
                if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Server001' }
                $config = Ensure-Config
                Update-Instance -InstanceName $name -Config $config
            }
            'start' {
                $name = Read-Host 'Instance name (for example Server001)'
                if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Server001' }
                $config = Ensure-Config
                Start-Instance -InstanceName $name -Config $config
            }
            'stop' {
                $name = Read-Host 'Instance name (for example Server001)'
                if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Server001' }
                Stop-Instance -InstanceName $name
            }
            'status' {
                $statusMode = Read-Host 'Show all instances? (Y/N)'
                if ($statusMode -match '^(Y|YES)$') {
                    Show-StatusForAll
                }
                else {
                    $name = Read-Host 'Instance name (for example Server001)'
                    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Server001' }
                    $status = Get-InstanceStatus -InstanceName $name
                    Write-Host "State      : $($status.State)"
                    Write-Host "PID        : $($status.PID)"
                    Write-Host "Port       : $($status.Port)"
                    Write-Host "QueryPort  : $($status.QueryPort)"
                    Write-Host "Crash Count: $($status.CrashCount)"
                    Write-Host "Log Age    : $($status.LogAge) minutes"
                }
            }
            'configuration' {
                Invoke-ConfigurationEditor
            }
            'help' {
                Show-HelpMenu
            }
            'exit' {
                return
            }
            default {
                Write-Host "Unknown command: $choice" -ForegroundColor Red
                Show-HelpMenu
            }
        }
    }
}

function Invoke-Command {
    <#
    .SYNOPSIS
        Processes a command-line invocation.
    .PARAMETER CommandName
        One of the supported V1 commands.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [string[]]$Arguments = @()
    )

    switch ($CommandName.ToLowerInvariant()) {
        'deploy' {
            $config = Ensure-Config
            Deploy-Instance -Config $config
        }
        'update' {
            $instanceName = $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($instanceName)) { $instanceName = 'Server001' }
            $config = Ensure-Config
            Update-Instance -InstanceName $instanceName -Config $config
        }
        'start' {
            $instanceName = $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($instanceName)) { $instanceName = 'Server001' }
            $config = Ensure-Config
            Start-Instance -InstanceName $instanceName -Config $config
        }
        'stop' {
            $instanceName = $Arguments[0]
            if ([string]::IsNullOrWhiteSpace($instanceName)) { $instanceName = 'Server001' }
            Stop-Instance -InstanceName $instanceName
        }
        'status' {
            if ($Arguments.Length -gt 0 -and -not [string]::IsNullOrWhiteSpace($Arguments[0])) {
                $status = Get-InstanceStatus -InstanceName $Arguments[0]
                Write-Host "State      : $($status.State)"
                Write-Host "PID        : $($status.PID)"
                Write-Host "Port       : $($status.Port)"
                Write-Host "QueryPort  : $($status.QueryPort)"
                Write-Host "Crash Count: $($status.CrashCount)"
                Write-Host "Log Age    : $($status.LogAge) minutes"
            }
            else {
                Show-StatusForAll
            }
        }
        'configuration' {
            Show-Configuration
        }
        'help' {
            Show-HelpMenu
        }
        'setup' {
            Ensure-Config | Out-Null
        }
        default {
            Write-Host "Unknown command: $CommandName" -ForegroundColor Red
            Show-HelpMenu
        }
    }
}

if ($Command) {
    $args = @()
    if ($MyInvocation.UnboundArguments.Count -gt 0) {
        $args = @($MyInvocation.UnboundArguments)
    }
    Invoke-Command -CommandName $Command -Arguments $args
}
else {
    Ensure-Config | Out-Null
    Show-Menu
}
