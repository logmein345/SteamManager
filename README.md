# SteamManager

SteamManager is an interactive PowerShell tool for deploying and managing Unreal dedicated server instances through SteamCMD.

It currently targets Steam AppID `4785920` and supports first-run configuration, instance deployment, updates, process control, status reporting, and inline help.

## Requirements

- Windows
- Windows PowerShell 5.1 or PowerShell 7+
- SteamCMD
- Access to the Steam server files for AppID `4785920`

SteamManager can search common locations for `steamcmd.exe`, or you can provide its full path during setup.

## Quick Start

1. Download or clone this repository.
2. Open PowerShell in the project directory.
3. Run the script:

	```powershell
	powershell.exe -ExecutionPolicy Bypass -File .\SteamManager.ps1
	```

4. Complete the first-run prompts. The configuration is saved as `config.json` next to the script.
5. At the `SteamManager>` prompt, enter `deploy` to download the server and create the first instance.

The default server root is `C:\GameServers`.

## Interactive Commands

| Command | Description |
| --- | --- |
| `Deploy` | Download or install a new server instance with SteamCMD |
| `Update` | Update an instance with SteamCMD |
| `Start` | Start an instance |
| `Stop` | Stop an instance |
| `Status` | Show status for one instance or all instances |
| `Configuration` | View or edit the current configuration |
| `Help` | Display the command list |
| `Exit` | Close the interactive menu |

Instance names default to `Server001` when a command needs a name and no name is supplied.

## Command-Line Usage

The `-Command` parameter runs a command without opening the interactive menu:

```powershell
.\SteamManager.ps1 -Command setup
.\SteamManager.ps1 -Command deploy
.\SteamManager.ps1 -Command update Server001
.\SteamManager.ps1 -Command start Server001
.\SteamManager.ps1 -Command stop Server001
.\SteamManager.ps1 -Command status
.\SteamManager.ps1 -Command status Server001
.\SteamManager.ps1 -Command configuration
.\SteamManager.ps1 -Command help
```

`setup` ensures that `config.json` exists. Commands that need SteamCMD will use anonymous SteamCMD login.

## Instance Layout

Instances are created below the configured server root and use incrementing names:

```text
C:\GameServers\
├── Server001\
│   ├── game files
│   ├── instance.json
│   └── StartServer.bat
├── Server002\
└── ...
```

Each instance receives a unique game port and query port. By default:

| Instance | Game port | Query port |
| --- | ---: | ---: |
| `Server001` | `7777` | `27015` |
| `Server002` | `7778` | `27016` |

Subsequent instances continue incrementing both ports by one.

## Configuration

The setup wizard and `Configuration` command manage these values:

- `SteamCmdPath`: Full path to `steamcmd.exe`
- `BaseRoot`: Root folder for server instances
- `AppId`: Steam application ID, defaulting to `4785920`
- `StartupTemplate`: Arguments passed to the server executable

The default startup template is:

```text
-log -port={PORT} -QueryPort={QUERYPORT}
```

Supported template variables are `{PORT}`, `{QUERYPORT}`, and `{NAME}`.

When the server is started, SteamManager adds Unreal's `-abslog` option and points it to the instance's `server.log` file. The `-log` option in the template tells the Unreal Dedicated Server to open a live log console window. If `-log` is removed, the server still writes to `server.log`, but no live log window is opened.

## Status

`Status` reports the instance state, process ID, game port, query port, crash count, and log age. The reported states are:

- `Healthy`
- `Running`
- `Stopped`
- `Crashed`

## Help

Inside the interactive menu:

- Enter `?` for the main help menu.
- Enter `?1` through `?7` for topic-specific help.

## Notes

- SteamManager scans an instance for an executable and ignores files containing `Editor`, `Launcher`, `CrashReport`, `unins`, or `steamcmd` in the name.
- `Stop` force-stops the recorded server process.
- Keep `config.json` and instance metadata backed up if you rely on custom paths or settings.
