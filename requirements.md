# Steam Manager V1 Requirements

AppID: 4785920

## Setup Wizard
- First-run setup wizard
- Save config.json
- Auto-detect SteamCMD folder
- Auto-discover steamcmd.exe
- Configuration summary before save

## Help System
- Help menu
- Menu help via ?1 ?2 etc
- Inline ? help for every config prompt
- Examples for every prompt

## Instance Layout

C:\GameServers
├── Server001
├── Server002
├── Server003

Each instance contains:
- game files
- instance.json
- StartServer.bat

## Deployment
- Anonymous steamcmd login
- Download AppID 4785920
- Auto increment folders

## Port Assignment

Server001:
Port 7777
QueryPort 27015

Server002:
Port 7778
QueryPort 27016

etc

## Startup Template

Default:

-log -port={PORT} -QueryPort={QUERYPORT}

Variables:
{PORT}
{QUERYPORT}
{NAME}

## Executable Detection

Deploy:
- scan for .exe files
- auto detect server executable
- ignore Editor, Launcher, CrashReport

Update:
- verify executable exists
- rescan if missing
- auto repair path

## Commands

Deploy
Update
Start
Stop
Status
Configuration
Help

## Status

Show:
- State
- PID
- Port
- QueryPort
- Crash Count
- Log Age

States:
Healthy
Running
Stopped
Crashed

## Comments

Fully documented PowerShell code
Comment-based help
Functions documented