# PowerShell Reverse Shell / Credential Theft Script

This repository contains a single PowerShell script, `autorun.ps1`, which is a malicious implant designed to establish a remote reverse shell, stage attacker tools, and capture keystrokes.

This project is provided for defensive research, detection engineering, malware analysis, and authorized security assessment purposes only. It should not be executed on any system unless it is part of a controlled, approved lab environment.

## Summary

The script performs the following actions:

- Connects to a hardcoded attacker IP address on TCP port 4444
- Downloads offensive tools into `C:\Lab`
- Creates a stealthy background keylogger
- Captures user keystrokes to `C:\Lab\keylog.txt`
- Exposes a remote command channel via PowerShell `Invoke-Expression`
- Allows an attacker to list staged tools, read keylogs, stop/start logging, and run arbitrary commands on the compromised host

## File(s)

- `autorun.ps1`

## Behavioral analysis

### 1. Reverse shell
The script attempts to connect to:

- IP: `192.168.100.109`
- Port: `4444`

If the connection succeeds, it reads commands from the socket and executes them locally with PowerShell. This gives remote operators interactive control over the victim machine.

The script reports a banner that includes:

- Computer name and username
- Tool staging path
- Keylogger status
- Available commands:
  - `tools`
  - `keys`
  - `keyon`
  - `keyoff`
  - `exit`

### 2. Tool staging
The script downloads several security tools into `C:\Lab`:

- `winPEASx64.exe`
- `mimikatz.zip`
- `chrome-injector-v0.20.0.zip`

These are publicly known offensive or post-exploitation tools, and the script is designed to stage them automatically for later use.

It also attempts to unpack the Mimikatz archive into a subdirectory called `C:\Lab\mimikatz`.

### 3. Keystroke capture
The script dynamically imports Win32 user32 APIs:

- `GetAsyncKeyState`
- `GetKeyboardState`
- `MapVirtualKey`
- `ToUnicode`

It then loops through virtual key codes and records any pressed keys into the Unicode log file at:

- `C:\Lab\keylog.txt`

This is a classic behavior for a keylogger and can capture:

- passwords
- usernames
- tokens
- messages
- commands
- clipboard-like typed data as it appears in user input fields

### 4. Remote command execution
The script supports remote commands through the socket connection. These commands are executed by PowerShell with `Invoke-Expression`, which means the attacker can run almost any PowerShell command on the compromised system.

This turns the host into a fully remote-controlled endpoint.

## Key technical indicators

The script contains multiple clear indicators of malicious behavior:

- Hardcoded external C2 server IP
- Remote TCP listener connection on port 4444
- Creation of `C:\Lab` directory
- Downloading malware / offensive tools from GitHub release URLs
- Win32 API keylogging through `ToUnicode`
- Local file persistence of stolen keystrokes
- Remote PowerShell command execution

## Likely purpose

This script is designed to perform post-exploitation activities such as:

- reconnaissance
- credential harvesting
- privilege escalation preparation
- remote access control
- exfiltration of user keystrokes and system output

## Defensive detections

This behavior may be detected by monitoring for:

- outbound connections to external IPs on uncommon ports
- creation of `C:\Lab` or similar directories
- downloads from GitHub release URLs in temporary or user-writable paths
- use of `Add-Type` with Win32 API imports for keyboard hooks or keylogging
- PowerShell runspaces used for background execution
- `Invoke-Expression` over network-driven commands
- creation or growth of files like `keylog.txt`

## Safe handling guidance

This repository should only be used in the following contexts:

- malware analysis sandbox
- internal red-team labs
- security tooling evaluation under explicit authorization
- detection engineering and IOCs development

Do not execute this script in live or production environments.

## Notes

The script contains comments indicating it is for authorized pentest use, but the capabilities are clearly malicious and can be abused for credential theft and remote control. It should be treated as malicious software for defensive and forensic purposes only.

## Disclaimer

This repository is not intended to be used for unauthorized computer access, malware deployment, credential theft, or attack automation. Use only in a controlled environment with necessary authorization.
