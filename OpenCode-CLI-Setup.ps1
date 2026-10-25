<#
================================================================================
 OpenCode CLI Setup
 Copyright (c) 2026 Mohamed Abd El-Hafez. All rights reserved.

 Independent community installer utility for the OpenCode CLI (Windows x64).
 This project is NOT affiliated with, endorsed by, or owned by the OpenCode
 project or its maintainers. "OpenCode" belongs to its respective owners.
================================================================================
#>
#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ==============================================================================
# 1. CONFIGURATION  (everything you may want to change lives here)
# ==============================================================================
$script:Cfg = [ordered]@{
    Title        = 'OpenCode CLI - Setup'
    Product      = 'OpenCode CLI'
    Author       = 'Mohamed Abd El-Hafez'
    Copyright    = 'Copyright (c) 2026 Mohamed Abd El-Hafez. All rights reserved.'
    Subtitle     = 'AI CODING AGENT ' + [char]0x2022 + ' AUTOMATE ' + [char]0x2022 + ' INTEGRATE ' + [char]0x2022 + ' BUILD MORE'
    ExeName      = 'opencode.exe'
    DefaultDir   = 'C:\Tools\OpenCode\CLI'

    # CLI 2 (current): the official npm packages used by the official OpenCode 2 installer script.
    V2LatestUrl  = 'https://opencode.ai/update/api/latest/cli/npm'
    NpmRegistry  = 'https://registry.npmjs.org'
    V2ListCount  = 6             # newest stable CLI 2 releases to offer
    # CLI 1 (legacy): official GitHub releases.
    Repo         = 'anomalyco/opencode'
    ApiBase      = 'https://api.github.com/repos'
    AssetName    = 'opencode-windows-x64.zip'
    AssetNameBaseline = 'opencode-windows-x64-baseline.zip'
    V1ListCount  = 3             # newest stable CLI 1 releases to offer
    TrustedHosts = '(^|\.)(github\.com|githubusercontent\.com|npmjs\.org|opencode\.ai)$'
    RequireHttps = $true

    MinExeBytes  = 1MB           # sanity floor for opencode.exe inside the archive
    MaxExeBytes  = 1GB           # zip-bomb guard
    MarkerName   = '.opencode-cli-setup.json'
    VersionTimeoutMs = 15000     # scans: a big binary can be slow on its first run (antivirus scan)
    InstallVerifyTimeoutMs = 45000
}

# Targeted, user-level locations that may hold an OpenCode CLI (no disk-wide scans).
function Get-WellKnownLocations {
    $list = New-Object System.Collections.ArrayList
    $up = $env:USERPROFILE; $la = $env:LOCALAPPDATA
    if ($up) {
        [void]$list.Add(@([IO.Path]::Combine($up, '.opencode', 'bin'), 'user'))
        [void]$list.Add(@([IO.Path]::Combine($up, 'scoop', 'apps', 'opencode', 'current'), 'scoop'))
        [void]$list.Add(@([IO.Path]::Combine($up, 'scoop', 'shims'), 'scoop'))
    }
    if ($la) {
        [void]$list.Add(@([IO.Path]::Combine($la, 'opencode', 'bin'), 'user'))
        [void]$list.Add(@([IO.Path]::Combine($la, 'Microsoft', 'WinGet', 'Links'), 'winget'))
    }
    if ($env:ChocolateyInstall) { [void]$list.Add(@([IO.Path]::Combine($env:ChocolateyInstall, 'bin'), 'choco')) }
    return $list
}

# ==============================================================================
# 2. TERMINAL LAYER  (rendering only - no installation logic in this section)
# ==============================================================================
$script:Ansi = $false
$script:Esc  = [string][char]27
$script:Ops  = New-Object System.Collections.ArrayList
$script:PanelWidth    = 78                      # total panel width including borders
$script:Ic   = @{}
$script:Pal  = @{
    text     = @(205, 214, 232, 'Gray')
    dim      = @(112, 126, 156, 'DarkGray')
    border   = @(58, 78, 128, 'DarkCyan')
    cyan     = @(0, 229, 255, 'Cyan')
    blue     = @(64, 132, 255, 'Cyan')
    logo_mid = @(64, 132, 255, 'Blue')
    purple   = @(178, 98, 255, 'Magenta')
    green    = @(72, 245, 160, 'Green')
    yellow   = @(255, 200, 84, 'Yellow')
    red      = @(255, 92, 112, 'Red')
    white    = @(245, 248, 255, 'White')
}
$script:BgRgb = @(9, 13, 26)           # deep navy / near-black

$script:LogoLines = @'
   ____                   ______          __        ________    ____
  / __ \____  ___  ____  / ____/___  ____/ /__     / ____/ /   /  _/
 / / / / __ \/ _ \/ __ \/ /   / __ \/ __  / _ \   / /   / /    / /  
/ /_/ / /_/ /  __/ / / / /___/ /_/ / /_/ /  __/  / /___/ /____/ /   
\____/ .___/\___/_/ /_/\____/\____/\__,_/\___/   \____/_____/___/   
    /_/                                                             
'@ -split "`r?`n"
$script:LogoW = 68

function Enable-VtMode {
    try {
        if (-not ('OcSetup.Native' -as [type])) {
            Add-Type -Namespace OcSetup -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out int m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, int m);
'@
        }
        $h = [OcSetup.Native]::GetStdHandle(-11); $m = 0
        if (-not [OcSetup.Native]::GetConsoleMode($h, [ref]$m)) { return $false }
        if (($m -band 4) -ne 0) { return $true }
        return [OcSetup.Native]::SetConsoleMode($h, ($m -bor 4))
    } catch { return $false }
}

function Initialize-Terminal {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
    try { $Host.UI.RawUI.WindowTitle = $script:Cfg.Title } catch {}
    try {
        $size = $Host.UI.RawUI.WindowSize
        if ($size.Width -lt 80) {
            $buf = $Host.UI.RawUI.BufferSize
            if ($buf.Width -lt 80) { $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80, $buf.Height) }
            $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(80, $size.Height)
        }
    } catch {}

    $script:Ansi = $false
    if (-not $env:NO_COLOR -and -not [Console]::IsOutputRedirected) {
        if ($env:WT_SESSION -or $env:ConEmuANSI -eq 'ON' -or $env:TERM_PROGRAM) { $script:Ansi = $true }
        elseif (Enable-VtMode) { $script:Ansi = $true }
    }
    if ($script:Ansi) {
        $script:Ic = @{ dot = [string][char]0x25CF; ok = [string][char]0x2713; bad = [string][char]0x2717; diamond = [string][char]0x25C6; prompt = [string][char]0x276F; arrow = [string][char]0x203A; bar = [string][char]0x2588; barOff = [string][char]0x2591 }
        $c = $script:BgRgb
        [Console]::Write(("{0}[48;2;{1};{2};{3}m{0}[2J{0}[H" -f $script:Esc, $c[0], $c[1], $c[2]))
    } else {
        $script:Ic = @{ dot = '*'; ok = '+'; bad = 'x'; diamond = '*'; prompt = '>'; arrow = '>'; bar = '#'; barOff = '-' }
    }
}

function Restore-Terminal {
    try {
        if ($script:Ansi) { [Console]::Write(("{0}[0m{0}[2J{0}[H" -f $script:Esc)) }
        else { [Console]::ResetColor() }
    } catch {}
}

function Clear-Screen {
    if ($script:Ansi) { [Console]::Write(("{0}[2J{0}[H" -f $script:Esc)) } else { Clear-Host }
}

# --- op buffer: build a screen in memory, then write it once -------------------
function New-Ops { $script:Ops = New-Object System.Collections.ArrayList }
function T  { param([string]$Text, [string]$C = 'text') [void]$script:Ops.Add(@($Text, $C, $null)) }
function NL { [void]$script:Ops.Add(@("`n", '', $null)) }
function Add-Erase {
    if ($script:Ansi) { [void]$script:Ops.Add(@(($script:Esc + '[2K'), 'text', $null)) }
    else { [void]$script:Ops.Add(@(((' ' * ($script:PanelWidth - 1)) + "`r"), 'text', $null)) }
}

function Write-Ops {
    $ops = $script:Ops
    New-Ops
    if ($script:Ansi) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($op in $ops) {
            $t = $op[0]
            if ($t -eq "`n") { [void]$sb.Append($script:Esc + "[K`n"); continue }
            $rgb = $op[2]
            if (-not $rgb -and $op[1]) { $rgb = $script:Pal[$op[1]] }
            if ($rgb) { [void]$sb.AppendFormat('{0}[38;2;{1};{2};{3}m', $script:Esc, $rgb[0], $rgb[1], $rgb[2]) }
            [void]$sb.Append($t)
        }
        [Console]::Write($sb.ToString())
    } else {
        foreach ($op in $ops) {
            if ($op[0] -eq "`n") { Write-Host ''; continue }
            if ($op[1]) { Write-Host -NoNewline -ForegroundColor $script:Pal[$op[1]][3] $op[0] }
            else { Write-Host -NoNewline $op[0] }
        }
    }
}

# --- layout helpers ------------------------------------------------------------
function Get-Shortened {
    param([string]$Text, [int]$Max)
    if ($Text.Length -le $Max) { return $Text }
    if ($Max -lt 8) { return $Text.Substring(0, [Math]::Max(1, $Max)) }
    $head = [Math]::Floor(($Max - 3) / 3); $tail = $Max - 3 - $head
    return $Text.Substring(0, $head) + '...' + $Text.Substring($Text.Length - $tail)
}

function Panel-Top {
    param([string]$Title = '')
    T ([string][char]0x256D) 'border'
    if ($Title) {
        T ([string][char]0x2500 + ' ') 'border'; T $Title 'cyan'; T ' ' 'border'
        T ([string][char]0x2500 * ($script:PanelWidth - 5 - $Title.Length)) 'border'
    } else { T ([string][char]0x2500 * ($script:PanelWidth - 2)) 'border' }
    T ([string][char]0x256E) 'border'; NL
}
function Panel-End {
    T ([string][char]0x2570) 'border'; T ([string][char]0x2500 * ($script:PanelWidth - 2)) 'border'; T ([string][char]0x256F) 'border'; NL
}
function Panel-Row {
    # usage: Panel-Row 'text1','color1','text2','color2',...
    param([string[]]$Seg)
    $inner = $script:PanelWidth - 4
    T ([string][char]0x2502 + ' ') 'border'
    $used = 0
    for ($i = 0; $i -lt $Seg.Count; $i += 2) {
        $txt = $Seg[$i]; $room = $inner - $used
        if ($txt.Length -gt $room) { $txt = Get-Shortened $txt $room }
        T $txt $Seg[$i + 1]; $used += $txt.Length
    }
    if ($used -lt $inner) { T (' ' * ($inner - $used)) 'text' }
    T (' ' + [string][char]0x2502) 'border'; NL
}
function Panel-Blank { Panel-Row '', 'text' }

function Add-Centered { param([string]$Text, [string]$C) T (' ' * [Math]::Max(0, [int](($script:PanelWidth - $Text.Length) / 2))) 'text'; T $Text $C }

function Add-Gradient {
    param([string]$Line)
    $steps = 16; $run = New-Object System.Text.StringBuilder; $runQ = -2
    $flush = {
        if ($run.Length -gt 0) {
            if ($runQ -eq -1) { T $run.ToString() 'text' }
            else {
                $t = $runQ / ($steps - 1)
                if ($t -lt 0.5) { $f = $t * 2; $a = $script:Pal.cyan; $b = $script:Pal.blue; $key = 'cyan' }
                else { $f = ($t - 0.5) * 2; $a = $script:Pal.blue; $b = $script:Pal.purple; $key = 'purple' }
                if ($t -ge 0.33 -and $t -lt 0.66) { $key = 'logo_mid' }
                $rgb = @([int]($a[0] + ($b[0] - $a[0]) * $f), [int]($a[1] + ($b[1] - $a[1]) * $f), [int]($a[2] + ($b[2] - $a[2]) * $f))
                [void]$script:Ops.Add(@($run.ToString(), $key, $rgb))
            }
            [void]$run.Clear()
        }
    }
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $q = if ($Line[$i] -eq ' ') { -1 } else { [Math]::Min($steps - 1, [int][Math]::Floor(($i / ($script:LogoW - 1)) * $steps)) }
        if ($q -ne $runQ) { & $flush; $runQ = $q }
        [void]$run.Append($Line[$i])
    }
    & $flush
}

# --- input ---------------------------------------------------------------------
function Read-OneKey {
    # returns a single upper-case character, 'ESC', '' (Enter) or $null (end of input)
    if ([Console]::IsInputRedirected) {
        $l = [Console]::In.ReadLine()
        if ($null -eq $l) { return $null }
        if ($l.Length -eq 0) { return '' }
        return $l.Substring(0, 1).ToUpperInvariant()
    }
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq [ConsoleKey]::Escape) { return 'ESC' }
    if ($k.Key -eq [ConsoleKey]::Enter) { return '' }
    return ([string]$k.KeyChar).ToUpperInvariant()
}

function Show-Prompt {
    param([string]$Text, [string]$Err = '')
    New-Ops; T "`r" 'text'; Add-Erase
    T ('  ' + $script:Ic.prompt + ' ') 'cyan'; T $Text 'text'
    if ($Err) { T ('  ' + $Err) 'red' }
    Write-Ops
}

function Read-Choice {
    # Valid: allowed characters. 'B' (or Esc) is returned as 'B' when Valid contains B. $null = input closed.
    param([string]$Valid, [string]$Prompt, [string]$Default = '')
    $err = ''
    while ($true) {
        Show-Prompt $Prompt $err
        $k = Read-OneKey
        if ($null -eq $k) { return $null }
        if ($k -eq '' -and $Default) { $k = $Default }
        if ($k -eq 'ESC' -and $Valid.Contains('B')) { $k = 'B' }
        if ($k.Length -eq 1 -and $Valid.Contains($k)) {
            New-Ops; T (' ' + $k) 'white'; NL; Write-Ops
            return $k
        }
        $err = 'Invalid choice.'
    }
}

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $err = ''
    while ($true) {
        Show-Prompt ("$Prompt $hint ") $err
        $k = Read-OneKey
        if ($null -eq $k -or $k -eq 'ESC') { New-Ops; T ' no' 'dim'; NL; Write-Ops; return $false }
        if ($k -eq '') { $k = if ($DefaultYes) { 'Y' } else { 'N' } }
        if ($k -eq 'Y') { New-Ops; T ' yes' 'white'; NL; Write-Ops; return $true }
        if ($k -eq 'N') { New-Ops; T ' no' 'white'; NL; Write-Ops; return $false }
        $err = 'Press Y or N.'
    }
}

function Read-Line {
    param([string]$Prompt)
    New-Ops; T ('  ' + $script:Ic.prompt + ' ') 'cyan'; T $Prompt 'text'; Write-Ops
    return [Console]::In.ReadLine()
}

function Wait-Key {
    param([string]$Text = 'Press any key to continue...')
    New-Ops; NL; T ('  ' + $Text) 'dim'; Write-Ops
    [void](Read-OneKey)
    New-Ops; NL; Write-Ops
}

function Write-Status {
    # level: ok | info | warn | err
    param([string]$Level, [string]$Message)
    New-Ops
    switch ($Level) {
        'ok'   { T ('  ' + $script:Ic.ok + ' ') 'green';  T $Message 'text' }
        'warn' { T '  ! ' 'yellow'; T $Message 'yellow' }
        'err'  { T ('  ' + $script:Ic.bad + ' ') 'red'; T $Message 'red' }
        default { T ('  ' + $script:Ic.arrow + ' ') 'cyan'; T $Message 'dim' }
    }
    NL; Write-Ops
}

function Show-Progress {
    param([long]$Done, [long]$Total)
    $width = 30
    New-Ops; T "`r" 'text'; Add-Erase
    T '  Downloading  ' 'dim'
    if ($Total -gt 0) {
        $pct = [Math]::Min(100, [int](($Done * 100) / $Total)); $fill = [int]($width * $pct / 100)
        T ($script:Ic.bar * $fill) 'cyan'; T ($script:Ic.barOff * ($width - $fill)) 'border'
        T ('  {0,3}%  {1} / {2}' -f $pct, (Format-Size $Done), (Format-Size $Total)) 'text'
    } else { T (Format-Size $Done) 'text' }
    Write-Ops
}

function Format-Size { param([double]$Bytes) if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) } return ('{0:N0} KB' -f ($Bytes / 1KB)) }

# --- screens -------------------------------------------------------------------
function Show-Brand {
    New-Ops
    NL
    $pad = ' ' * [int](($script:PanelWidth - $script:LogoW) / 2)
    foreach ($line in $script:LogoLines) { T $pad 'text'; Add-Gradient $line; NL }
    NL
    Add-Centered $script:Cfg.Subtitle 'blue'; NL
    NL
    Panel-Top
    $d = $script:Ic.diamond
    Panel-Row ($d + ' '), 'cyan', 'Windows x64 Installer', 'text', '     ', 'text', ($d + ' '), 'cyan', 'Official OpenCode CLI package source', 'text'
    Panel-Row ($d + ' '), 'purple', 'Multi-version support', 'text', '     ', 'text', ($d + ' '), 'purple', 'by ', 'dim', $script:Cfg.Author, 'white'
    Panel-Row $script:Cfg.Copyright, 'dim'
    Panel-Row 'Independent community utility - not affiliated with OpenCode.', 'dim'
    Panel-End
    Write-Ops
}

function Show-SubHeader {
    param([string]$Title)
    Clear-Screen
    New-Ops; NL
    T '  OpenCode CLI' 'cyan'; T ' - Setup  ' 'text'; T ($script:Ic.arrow + ' ') 'border'; T $Title 'purple'; NL
    T ('  ' + [string][char]0x2500 * ($script:PanelWidth - 4)) 'border'; NL; NL
    Write-Ops
}

function Show-StatusPanel {
    param($Scan)
    New-Ops; NL
    Panel-Top 'INSTALLATION STATUS'
    switch ($Scan.Status) {
        'Found' {
            $n = @($Scan.Items).Count
            Panel-Row ($script:Ic.dot + ' '), 'green', ("FOUND - $n OpenCode CLI installation(s)"), 'green'
            foreach ($it in $Scan.Items) {
                $ver = if ($it.Version) { 'v' + $it.Version } else { 'version unknown' }
                $tag = '[' + $it.Source + $(if ($it.Owned) { ', managed by this installer' } else { '' }) + ']'
                Panel-Row '   ', 'text', $ver, $(if ($it.Version) { 'white' } else { 'yellow' }), ('  ' + $tag), 'dim'
                Panel-Row '   ', 'text', $it.Path, 'dim'
            }
        }
        'Incomplete' {
            Panel-Row ($script:Ic.dot + ' '), 'red', 'DETECTION INCOMPLETE - some locations could not be checked', 'red'
        }
        default {
            Panel-Row ($script:Ic.dot + ' '), 'yellow', 'NOT FOUND in the locations checked', 'yellow'
        }
    }
    foreach ($e in $Scan.Errors) { Panel-Row '   ! ', 'yellow', $e, 'yellow' }
    $deep = [bool]($Scan.PSObject.Properties['DeepDone'] -and $Scan.DeepDone)
    if ($deep) {
        Panel-Row 'All drives were searched. Folders without permission are skipped.', 'dim'
    } else {
        Panel-Row 'Quick check: install folder, PATH, common locations.', 'dim'
        Panel-Row 'Not a full-disk search - use "Scan all drives" for that.', 'dim'
    }
    Panel-End
    Write-Ops
}

function Show-MainScreen {
    param($Scan)
    Clear-Screen
    Show-Brand
    Show-StatusPanel $Scan
    New-Ops; NL
    Panel-Top 'MAIN MENU'
    Panel-Row ' 1 ', 'cyan', '  Install / Update OpenCode CLI', 'white'
    Panel-Row '       Download the official release and install it safely', 'dim'
    Panel-Blank
    Panel-Row ' 2 ', 'purple', '  Uninstall OpenCode CLI', 'white'
    Panel-Row '       Remove one selected CLI installation (data is never touched)', 'dim'
    Panel-Blank
    Panel-Row ' 3 ', 'blue', '  Scan all drives', 'white'
    Panel-Row '       Search every drive and partition for installed copies', 'dim'
    Panel-Blank
    Panel-Row ' 4 ', 'dim', '  Exit', 'white'
    Panel-End
    Write-Ops
}

# ==============================================================================
# 3. PATHS, PROCESSES, STATE
# ==============================================================================
function ConvertTo-InstallPath {
    # Normalises user input: quotes, %VARS%, ~, validates, returns @{Ok; Path; Error}
    param([string]$Raw)
    $fail = { param($m) [pscustomobject]@{ Ok = $false; Path = $null; Error = $m } }
    if ($null -eq $Raw) { return & $fail 'No path entered.' }
    $s = $Raw.Trim()
    if ($s.Length -ge 2 -and (($s[0] -eq '"' -and $s[$s.Length - 1] -eq '"') -or ($s[0] -eq "'" -and $s[$s.Length - 1] -eq "'"))) {
        $s = $s.Substring(1, $s.Length - 2).Trim()
    }
    $s = $s.Trim('"')
    if ($s.Length -eq 0) { return & $fail 'No path entered.' }
    $s = [Environment]::ExpandEnvironmentVariables($s)
    if ($s -eq '~' -or $s.StartsWith('~\') -or $s.StartsWith('~/')) {
        $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
        $s = $home_ + $s.Substring(1)
    }
    if ($s.StartsWith('\\')) { return & $fail 'Network and device paths are not supported. Use a local folder such as C:\Tools\OpenCode\CLI.' }
    if ($s.IndexOfAny([char[]]'*?<>|"') -ge 0) { return & $fail 'The path contains characters that are not allowed (* ? < > | ").' }
    if ($s.Length -gt 2 -and $s.IndexOf(':', 2) -ge 0) { return & $fail 'A colon is only allowed after the drive letter.' }
    foreach ($c in [IO.Path]::GetInvalidPathChars()) { if ($s.IndexOf($c) -ge 0) { return & $fail 'The path contains invalid characters.' } }
    if (-not [IO.Path]::IsPathRooted($s)) { return & $fail 'Enter a full path, for example C:\Tools\OpenCode\CLI.' }
    try { $full = [IO.Path]::GetFullPath($s) } catch { return & $fail ('Invalid path: ' + $_.Exception.Message) }
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) { $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
    if ($full.Length -le $root.Length) { return & $fail 'Choose a folder, not the root of a drive.' }
    if ($env:SystemRoot -and ($full -ieq $env:SystemRoot -or $full.StartsWith($env:SystemRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
        return & $fail 'Installing inside the Windows folder is not allowed.'
    }
    if (Test-Path -LiteralPath $full -PathType Leaf) { return & $fail 'That path is an existing file, not a folder.' }
    return [pscustomobject]@{ Ok = $true; Path = $full; Error = $null }
}

function Test-DirWritable {
    # Creates the directory if needed. Returns @{Ok; Created; Error}
    param([string]$Dir)
    $created = $false
    try {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { [void][IO.Directory]::CreateDirectory($Dir); $created = $true }
        $probe = [IO.Path]::Combine($Dir, ('.write-test-' + [guid]::NewGuid().ToString('N')))
        [IO.File]::WriteAllText($probe, 'x'); [IO.File]::Delete($probe)
        return [pscustomobject]@{ Ok = $true; Created = $created; Error = $null }
    } catch {
        if ($created) { try { [IO.Directory]::Delete($Dir) } catch {} }
        return [pscustomobject]@{ Ok = $false; Created = $false; Error = $_.Exception.Message }
    }
}

function Invoke-Exe {
    # Runs "<exe> --version" with a timeout and without shell parsing. Returns @{Ok; Version; Output; Error; TimedOut}
    param([string]$Path, [string]$Arguments = '--version', [int]$TimeoutMs = 0)
    if ($TimeoutMs -le 0) { $TimeoutMs = $script:Cfg.VersionTimeoutMs }
    $r = [pscustomobject]@{ Ok = $false; Version = $null; Output = ''; Error = ''; TimedOut = $false; ExitCode = $null }
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Path; $psi.Arguments = $Arguments
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.WorkingDirectory = [IO.Path]::GetTempPath()
        $p = [System.Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            $r.TimedOut = $true; $r.Error = "Timed out after $([int]($TimeoutMs / 1000)) s."
            return $r
        }
        $p.WaitForExit()
        $r.Output = ([string]$o.Result).Trim(); $r.Error = ([string]$e.Result).Trim(); $r.ExitCode = $p.ExitCode
        $m = [regex]::Match($r.Output + ' ' + $r.Error, '\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)\b')
        if ($p.ExitCode -eq 0 -and $m.Success) { $r.Ok = $true; $r.Version = $m.Groups[1].Value }
        return $r
    } catch {
        $r.Error = $_.Exception.Message
        return $r
    } finally { if ($p) { $p.Dispose() } }
}

$script:VerCache = @{}
function Get-ExeVersionCached {
    param([string]$Path)
    try {
        $fi = New-Object IO.FileInfo($Path)
        $key = '{0}|{1}|{2}' -f $Path.ToLowerInvariant(), $fi.Length, $fi.LastWriteTimeUtc.Ticks
    } catch { $key = $Path.ToLowerInvariant() }
    if (-not $script:VerCache.ContainsKey($key)) { $script:VerCache[$key] = Invoke-Exe -Path $Path }
    return $script:VerCache[$key]
}

# --- ownership / classification ------------------------------------------------
function Get-MarkerPath { param([string]$Dir) [IO.Path]::Combine($Dir, $script:Cfg.MarkerName) }

function Read-Marker {
    param([string]$ExePath)
    try {
        $mp = Get-MarkerPath ([IO.Path]::GetDirectoryName($ExePath))
        if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) { return $null }
        $m = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($m.Tool -ne 'OpenCode-CLI-Setup') { return $null }
        if ([string]$m.ExePath -ine $ExePath) { return $null }
        return $m
    } catch { return $null }
}

function Test-IsDesktopApp {
    # Heuristic: never treat the OpenCode Desktop app folder as a CLI install.
    param([string]$ExePath)
    try {
        $dir = [IO.Path]::GetDirectoryName($ExePath)
        if ($dir -like '*\Programs\OpenCode' -or $dir -like '*\Programs\opencode-desktop*') { return $true }
        if (Test-Path -LiteralPath ([IO.Path]::Combine($dir, 'resources')) -PathType Container) { return $true }
        if (@(Get-ChildItem -LiteralPath $dir -Filter 'Uninstall*.exe' -File -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
    } catch {}
    return $false
}

function Get-PackageManager {
    param([string]$ExePath)
    if ($ExePath -match '\\scoop\\') { return 'Scoop' }
    if ($ExePath -match '\\chocolatey\\') { return 'Chocolatey' }
    if ($ExePath -match '\\WinGet\\') { return 'WinGet' }
    if ($ExePath -match '\\node_modules\\|\\npm\\') { return 'npm' }
    return $null
}

# --- state: remember folders this installer installed into ---------------------
function Get-StatePath {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    [IO.Path]::Combine($base, 'OpenCode-CLI-Setup', 'installs.json')
}
function Get-KnownDirs {
    try {
        $p = Get-StatePath
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            return @($j.Dirs | Where-Object { $_ })
        }
    } catch {}
    return @()
}
function Save-KnownDirs {
    param([string[]]$Dirs)
    try {
        $p = Get-StatePath
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))
        $json = (@{ Dirs = @($Dirs | Sort-Object -Unique) } | ConvertTo-Json -Compress)
        [IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}
function Add-KnownDir { param([string]$Dir) Save-KnownDirs (@(Get-KnownDirs) + $Dir) }
function Remove-KnownDir { param([string]$Dir) Save-KnownDirs @(Get-KnownDirs | Where-Object { $_ -ine $Dir }) }

# ==============================================================================
# 4. DETECTION  (targeted locations only)
# ==============================================================================
function New-InstallItem {
    param([string]$ExePath, [string]$Source)
    $v = Get-ExeVersionCached $ExePath
    $marker = Read-Marker $ExePath
    [pscustomobject]@{
        Path    = $ExePath
        Dir     = [IO.Path]::GetDirectoryName($ExePath)
        Source  = $Source
        Version = $v.Version
        Owned   = [bool]$marker
        Marker  = $marker
        Manager = Get-PackageManager $ExePath
    }
}

function Find-Installations {
    $seen = @{}; $items = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $exeName = $script:Cfg.ExeName

    $probe = {
        param([string]$Dir, [string]$Source)
        try {
            if ([string]::IsNullOrWhiteSpace($Dir)) { return }
            $d = $Dir.Trim().Trim('"')
            if (-not [IO.Path]::IsPathRooted($d)) { return }
            $exe = [IO.Path]::Combine($d, $exeName)
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return }
            $canon = (Get-Item -LiteralPath $exe -Force).FullName
            $key = $canon.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { return }
            $seen[$key] = $true
            if (Test-IsDesktopApp $canon) { return }
            [void]$items.Add((New-InstallItem -ExePath $canon -Source $Source))
        } catch { [void]$errors.Add(("Could not check {0}: {1}" -f (Get-Shortened $Dir 40), $_.Exception.Message)) }
    }

    & $probe $script:Cfg.DefaultDir 'default'
    foreach ($d in (Get-KnownDirs)) { & $probe $d 'installer' }
    foreach ($loc in (Get-WellKnownLocations)) { & $probe $loc[0] $loc[1] }
    try {
        if ($env:LOCALAPPDATA) {
            $pk = [IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'WinGet', 'Packages')
            if (Test-Path -LiteralPath $pk -PathType Container) {
                foreach ($dd in (Get-ChildItem -LiteralPath $pk -Directory -Filter 'SST.opencode*' -ErrorAction Stop)) { & $probe $dd.FullName 'winget' }
            }
        }
    } catch { [void]$errors.Add('Could not check the WinGet package folder: ' + $_.Exception.Message) }
    $pathDirs = @()
    try { $pathDirs = @(([Environment]::GetEnvironmentVariable('PATH') -split [IO.Path]::PathSeparator) | Where-Object { $_ }) }
    catch { [void]$errors.Add('Could not read PATH: ' + $_.Exception.Message) }
    foreach ($pd in $pathDirs) { & $probe $pd 'PATH' }

    $status = 'NotFound'
    if ($items.Count -gt 0) { $status = 'Found' } elseif ($errors.Count -gt 0) { $status = 'Incomplete' }
    [pscustomobject]@{ Status = $status; Items = @($items); Errors = @($errors); DeepDone = $false }
}

# --- deep search: every fixed/removable drive (uses the built-in "dir /s", very fast) ---
function New-ScanResult {
    param($Items, $Errors, [bool]$Deep)
    $status = 'NotFound'
    if (@($Items).Count -gt 0) { $status = 'Found' } elseif (@($Errors).Count -gt 0) { $status = 'Incomplete' }
    [pscustomobject]@{ Status = $status; Items = @($Items); Errors = @($Errors); DeepDone = $Deep }
}

function Get-SearchRoots {
    try {
        return @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') } | ForEach-Object { $_.Name })
    } catch { return @() }
}

function Search-Drive {
    # Lists every opencode.exe on one drive. Unreadable folders are skipped silently by "dir".
    param([string]$Root, [scriptblock]$OnProgress)
    $cmd = if ($env:ComSpec) { $env:ComSpec } else { 'cmd.exe' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $cmd
    $psi.Arguments = '/d /c chcp 65001 >nul & dir "' + [IO.Path]::Combine($Root, $script:Cfg.ExeName) + '" /s /b /a:-d 2>nul'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        if ($OnProgress) { & $OnProgress $Root 0 }
        while (-not $p.WaitForExit(250)) { if ($OnProgress) { & $OnProgress $Root ([int]$sw.Elapsed.TotalSeconds) } }
        $p.WaitForExit()
        return @(([string]$o.Result) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } finally { $p.Dispose() }
}

function Test-DeepCandidate {
    # Cheap checks first, so we only ever run files that really are a 64-bit OpenCode-sized executable.
    param([string]$Path)
    try {
        if ($Path -match '(?i)[\\/]\$Recycle\.Bin[\\/]|[\\/]WinSxS[\\/]|[\\/]OpenCodeCLISetup-') { return $false }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $Path -Force).Length -lt $script:Cfg.MinExeBytes) { return $false }
        if (Test-PeX64 $Path) { return $false }
        if (Test-IsDesktopApp $Path) { return $false }
        return $true
    } catch { return $false }
}

function Find-DeepInstallations {
    param($Existing, [scriptblock]$OnProgress)
    $items = New-Object System.Collections.ArrayList
    $errors = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($i in @($Existing.Items)) { [void]$items.Add($i); $seen[$i.Path.ToLowerInvariant()] = $true }
    $roots = @(Get-SearchRoots)
    if ($roots.Count -eq 0) { [void]$errors.Add('No drives could be listed.') }
    foreach ($root in $roots) {
        try {
            foreach ($path in @(Search-Drive $root $OnProgress)) {
                if (-not (Test-DeepCandidate $path)) { continue }
                $canon = (Get-Item -LiteralPath $path -Force).FullName
                $key = $canon.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$items.Add((New-InstallItem -ExePath $canon -Source 'drive scan'))
            }
        } catch { [void]$errors.Add(("Could not search {0}: {1}" -f $root, $_.Exception.Message)) }
    }
    return New-ScanResult @($items) @($errors) $true
}

function Update-Scan {
    # Fast refresh after install/uninstall; keeps earlier all-drive results that still exist.
    $q = Find-Installations
    $prev = $script:Scan
    if ($prev -and $prev.PSObject.Properties['DeepDone'] -and $prev.DeepDone) {
        $items = New-Object System.Collections.ArrayList; $keys = @{}
        foreach ($i in $q.Items) { [void]$items.Add($i); $keys[$i.Path.ToLowerInvariant()] = $true }
        foreach ($i in $prev.Items) {
            if (-not $keys.ContainsKey($i.Path.ToLowerInvariant()) -and (Test-Path -LiteralPath $i.Path -PathType Leaf)) { [void]$items.Add($i) }
        }
        return New-ScanResult @($items) @($q.Errors) $true
    }
    return $q
}

# ==============================================================================
# 5. RELEASE RESOLUTION, DOWNLOAD, ARCHIVE VALIDATION
# ==============================================================================
function Get-Prop {
    param($Obj, [string]$Name, $Default = $null)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) { return $Obj.PSObject.Properties[$Name].Value }
    return $Default
}

function Invoke-TextGet {
    param([string]$Url, [hashtable]$Headers = @{})
    $c = $script:Cfg
    $uri = [uri]$Url
    if ($c.RequireHttps -and $uri.Scheme -ne 'https') { throw 'Refusing a non-HTTPS request.' }
    if ($uri.Host -notmatch $c.TrustedHosts) { throw "Refusing a request to an untrusted host: $($uri.Host)" }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd('OpenCode-CLI-Setup/1.0')
    foreach ($k in $Headers.Keys) { [void]$client.DefaultRequestHeaders.TryAddWithoutValidation($k, [string]$Headers[$k]) }
    try {
        $resp = $client.GetAsync($Url).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { throw ('HTTP {0} {1} ({2})' -f [int]$resp.StatusCode, $resp.ReasonPhrase, $uri.Host) }
        return $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    } finally { $client.Dispose() }
}
function Invoke-JsonGet { param([string]$Url, [hashtable]$Headers = @{}) return (Invoke-TextGet $Url $Headers) | ConvertFrom-Json }

function Select-StableVersions {
    # Keeps only final releases (x.y.z, no beta/dev/rc suffix), newest first, numerically sorted.
    param([string[]]$Names, [int]$Max)
    return @($Names | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Select-Object -Unique | Sort-Object { [version]$_ } -Descending | Select-Object -First $Max)
}

function Test-Avx2 {
    # Same check the official installer uses to decide between the normal and the "baseline" build.
    try {
        if (-not ('OcSetup.Cpu' -as [type])) {
            Add-Type -Namespace OcSetup -Name Cpu -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int f);
'@
        }
        return [bool][OcSetup.Cpu]::IsProcessorFeaturePresent(40)
    } catch { return $false }
}

function Get-ReleaseCatalog {
    # Returns @{Entries; Notes}. Only stable releases; newest CLI 2 first, then the newest CLI 1 releases.
    $c = $script:Cfg
    $entries = New-Object System.Collections.ArrayList
    $notes = New-Object System.Collections.ArrayList
    try {
        # The official update service only tells us the package scope. The registry is the source of truth
        # for which versions exist, so a missing or changed answer must never break the list.
        $scope = '@opencode'
        try {
            $meta = Invoke-JsonGet $c.V2LatestUrl
            $pk = [string](Get-Prop (Get-Prop $meta 'metadata' $null) 'package' ([string](Get-Prop $meta 'package' '')))
            if ($pk -match '^(@[^/]+)/cli$') { $scope = $Matches[1] }
        } catch {}
        $pkg = "$scope/cli-windows-x64"
        # Raw text on purpose: the registry document is large and lists every beta/dev build too.
        $raw = Invoke-TextGet ($c.NpmRegistry + '/' + $pkg.Replace('/', '%2f')) @{ Accept = 'application/vnd.npm.install-v1+json' }
        $names = @([regex]::Matches($raw, '"version":"(\d+\.\d+\.\d+)"') | ForEach-Object { $_.Groups[1].Value })
        $i = 0
        foreach ($v in (Select-StableVersions $names $c.V2ListCount)) {
            [void]$entries.Add([pscustomobject]@{ Line = 2; Version = $v; Scope = $scope; Assets = $null; Latest = ($i -eq 0) }); $i++
        }
        if ($i -eq 0) { [void]$notes.Add('No stable CLI 2 release was found.') }
    } catch { [void]$notes.Add('CLI 2 list unavailable: ' + $_.Exception.Message) }
    try {
        # GitHub releases now contain multiple major lines. Do not inspect only the
        # first 30 entries: those can be dominated by newer releases and hide CLI 1.
        # Page through stable releases until we find the requested CLI 1 builds.
        $n = 0
        $seen = @{}
        for ($page = 1; $page -le 10 -and $n -lt $c.V1ListCount; $page++) {
            $url = "{0}/{1}/releases?per_page=100&page={2}" -f $c.ApiBase, $c.Repo, $page
            $response = Invoke-JsonGet $url
            if ($null -eq $response) { break }
            # GitHub returns an array for a release page, but rate-limit/proxy/error
            # responses are JSON objects. Do not enumerate those objects as releases.
            if ($response -isnot [System.Array]) {
                $apiMessage = [string](Get-Prop $response 'message' '')
                if ($apiMessage) { throw ("GitHub API returned an error: " + $apiMessage) }
                throw 'GitHub API returned an unexpected response (expected a release array).'
            }
            $rels = @($response)
            if ($rels.Count -eq 0) { break }
            foreach ($r in $rels) {
                if ($n -ge $c.V1ListCount) { break }
                # GitHub's release schema can vary across proxies/older records; use
                # safe property access under StrictMode rather than assuming every field exists.
                if ([bool](Get-Prop $r 'draft' $false) -or [bool](Get-Prop $r 'prerelease' $false)) { continue }
                $tag = [string](Get-Prop $r 'tag_name' '')
                $m = [regex]::Match($tag, '^v(1\.\d+\.\d+)$')
                if (-not $m.Success -or $seen.ContainsKey($m.Groups[1].Value)) { continue }
                $assetsRaw = Get-Prop $r 'assets' @()
                $assets = @($assetsRaw)
                # Asset names are matched case-insensitively to tolerate GitHub metadata casing.
                $asset = @($assets | Where-Object { [string](Get-Prop $_ 'name' '') -ieq $c.AssetName } | Select-Object -First 1)
                if ($asset.Count -eq 0) { continue }
                $seen[$m.Groups[1].Value] = $true
                [void]$entries.Add([pscustomobject]@{ Line = 1; Version = $m.Groups[1].Value; Scope = $null; Assets = $assets; Latest = ($n -eq 0) })
                $n++
            }
        }
        if ($n -eq 0) { [void]$notes.Add('No compatible stable CLI 1 release with the expected Windows x64 ZIP asset was found in the checked GitHub release pages.') }
    } catch { [void]$notes.Add('CLI 1 list unavailable: ' + $_.Exception.Message) }
    return [pscustomobject]@{ Entries = @($entries); Notes = @($notes) }
}

function Resolve-Release {
    # Turns a chosen catalog entry into a concrete download (URL + integrity value).
    param($Entry)
    $c = $script:Cfg
    $avx2 = Test-Avx2
    if ($Entry.Line -eq 2) {
        $target = if ($avx2) { 'windows-x64' } else { 'windows-x64-baseline' }
        $pkg = '{0}/cli-{1}' -f $Entry.Scope, $target
        try { $doc = Invoke-JsonGet ('{0}/{1}/{2}' -f $c.NpmRegistry, $pkg.Replace('/', '%2f'), $Entry.Version) }
        catch {
            if ($_.Exception.Message -like 'HTTP 404*') { throw "CLI 2 $($Entry.Version) is not available for $target." }
            throw
        }
        $dist = Get-Prop $doc 'dist' $null
        $tar = [string](Get-Prop $dist 'tarball' '')
        if (-not $tar) { throw 'The registry returned no download link for this version.' }
        return [pscustomobject]@{
            Version = $Entry.Version; Line = 2; Url = $tar; Sha256 = $null; Integrity = [string](Get-Prop $dist 'integrity' ''); Kind = 'tgz'
            Variant = $(if ($avx2) { 'standard' } else { 'baseline (CPU without AVX2)' }); Note = $null; Display = ('CLI 2 - ' + $Entry.Version)
        }
    }
    $name = $c.AssetName; $variant = 'standard'; $note = $null
    if (-not $avx2) {
        if (@($Entry.Assets | Where-Object { $_.name -eq $c.AssetNameBaseline }).Count) { $name = $c.AssetNameBaseline; $variant = 'baseline (CPU without AVX2)' }
        else { $note = 'This CPU lacks AVX2 and no baseline build exists for this release; it may not run.' }
    }
    $asset = @($Entry.Assets | Where-Object { $_.name -eq $name }) | Select-Object -First 1
    if (-not $asset) { throw "Release $($Entry.Version) does not contain $name." }
    $sha = $null; $dg = [string](Get-Prop $asset 'digest' '')
    if ($dg -match '^sha256:([0-9a-fA-F]{64})$') { $sha = $Matches[1].ToLowerInvariant() }
    return [pscustomobject]@{ Version = $Entry.Version; Line = 1; Url = [string]$asset.browser_download_url; Sha256 = $sha; Integrity = ''; Kind = 'zip'; Variant = $variant; Note = $note; Display = ('CLI 1 - ' + $Entry.Version) }
}

function Save-Download {
    param([string]$Url, [string]$OutFile, [scriptblock]$OnProgress)
    $c = $script:Cfg
    $uri = [uri]$Url
    if ($c.RequireHttps -and $uri.Scheme -ne 'https') { throw 'Refusing to download over a non-HTTPS connection.' }
    if ($uri.Host -notmatch $c.TrustedHosts) { throw "Refusing to download from an untrusted host: $($uri.Host)" }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(60)
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd('OpenCode-CLI-Setup/1.0')
    $resp = $null; $in = $null; $out = $null
    try {
        $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { throw ('Download failed: HTTP {0} {1}' -f [int]$resp.StatusCode, $resp.ReasonPhrase) }
        $final = $resp.RequestMessage.RequestUri
        if ($final.Host -notmatch $c.TrustedHosts) { throw "The download was redirected to an untrusted host: $($final.Host)" }
        $total = [long]0
        if ($resp.Content.Headers.ContentLength) { $total = [long]$resp.Content.Headers.ContentLength }
        $in = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $out = New-Object IO.FileStream($OutFile, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buf = New-Object byte[] 81920; $done = [long]0
        $sw = [Diagnostics.Stopwatch]::StartNew(); $last = -1000
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $done += $n
            if ($OnProgress -and ($sw.ElapsedMilliseconds - $last) -ge 120) { $last = $sw.ElapsedMilliseconds; & $OnProgress $done $total }
        }
        $out.Flush()
        if ($OnProgress) { & $OnProgress $done $(if ($total -gt 0) { $total } else { $done }); New-Ops; NL; Write-Ops }
        if ($total -gt 0 -and $done -ne $total) { throw ("Incomplete download: received {0} of {1} bytes." -f $done, $total) }
        if ($done -eq 0) { throw 'The download was empty.' }
        return [pscustomobject]@{ Bytes = $done; FinalUrl = $final.AbsoluteUri }
    } finally {
        if ($out) { $out.Dispose() }; if ($in) { $in.Dispose() }
        if ($resp) { $resp.Dispose() }; $client.Dispose()
    }
}

function Test-ZipPackage {
    # Validates the archive WITHOUT extracting. Returns @{Ok; Error; EntryName; Length}
    param([string]$ZipPath)
    $bad = { param($m) [pscustomobject]@{ Ok = $false; Error = $m; EntryName = $null; Length = 0 } }
    try {
        $fs = [IO.File]::OpenRead($ZipPath)
        try { $magic = New-Object byte[] 4; [void]$fs.Read($magic, 0, 4) } finally { $fs.Dispose() }
        if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) { return & $bad 'The file is not a ZIP archive (bad signature).' }
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $matches_ = New-Object System.Collections.ArrayList
            foreach ($e in $zip.Entries) {
                $full = $e.FullName.Replace('\', '/')
                if ($full.StartsWith('/') -or $full -match '(^|/)\.\.(/|$)' -or $full -match '^[A-Za-z]:') { return & $bad "Unsafe path inside archive: $($e.FullName)" }
                if ($e.Name -ieq $script:Cfg.ExeName) { [void]$matches_.Add($e) }
            }
            if ($matches_.Count -eq 0) { return & $bad "The archive does not contain $($script:Cfg.ExeName)." }
            $pick = @($matches_ | Sort-Object { $_.FullName.Length })[0]
            if ($matches_.Count -gt 1 -and @($matches_ | Where-Object { $_.FullName.Length -eq $pick.FullName.Length }).Count -gt 1) {
                return & $bad "The archive contains several copies of $($script:Cfg.ExeName); refusing to guess."
            }
            if ($pick.Length -lt $script:Cfg.MinExeBytes) { return & $bad ("{0} in the archive is only {1} bytes - this does not look like a real build." -f $pick.Name, $pick.Length) }
            if ($pick.Length -gt $script:Cfg.MaxExeBytes) { return & $bad "$($pick.Name) in the archive is unreasonably large." }
            return [pscustomobject]@{ Ok = $true; Error = $null; EntryName = $pick.FullName; Length = $pick.Length }
        } finally { $zip.Dispose() }
    } catch [IO.InvalidDataException] {
        return & $bad 'The ZIP archive is corrupt or incomplete.'
    } catch {
        return & $bad ('Could not read the archive: ' + $_.Exception.Message)
    }
}

function Expand-ZipEntry {
    # Streams exactly one entry to a file we name ourselves (no path from the archive is ever used).
    param([string]$ZipPath, [string]$EntryName, [string]$OutFile)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $e = $zip.GetEntry($EntryName)
        if (-not $e) { throw "Archive entry vanished: $EntryName" }
        $in = $e.Open(); $out = [IO.File]::Create($OutFile)
        try { $in.CopyTo($out) } finally { $out.Dispose(); $in.Dispose() }
    } finally { $zip.Dispose() }
}

function Test-PeX64 {
    # Returns $null when the file is a 64-bit x86-64 Windows executable, otherwise an error string.
    param([string]$File)
    try {
        $fs = [IO.File]::OpenRead($File)
        try {
            $b = New-Object byte[] 64
            if ($fs.Read($b, 0, 64) -lt 64 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return 'The file is not a Windows executable (missing MZ header).' }
            $off = [BitConverter]::ToInt32($b, 60)
            if ($off -lt 64 -or $off -gt ($fs.Length - 6)) { return 'The executable header is invalid.' }
            [void]$fs.Seek($off, [IO.SeekOrigin]::Begin)
            $h = New-Object byte[] 6; [void]$fs.Read($h, 0, 6)
            if ($h[0] -ne 0x50 -or $h[1] -ne 0x45 -or $h[2] -ne 0 -or $h[3] -ne 0) { return 'The executable header is invalid (missing PE signature).' }
            $machine = [BitConverter]::ToUInt16($h, 4)
            if ($machine -ne 0x8664) { return ('The executable is not x64 (machine type 0x{0:X4}).' -f $machine) }
            return $null
        } finally { $fs.Dispose() }
    } catch { return 'Could not inspect the executable: ' + $_.Exception.Message }
}

function Read-Exact {
    param($Stream, [byte[]]$Buf, [int]$Count)
    $got = 0
    while ($got -lt $Count) { $n = $Stream.Read($Buf, $got, $Count - $got); if ($n -le 0) { break }; $got += $n }
    return $got
}
function Skip-Bytes {
    param($Stream, [long]$Count)
    $b = New-Object byte[] 81920
    while ($Count -gt 0) {
        $n = $Stream.Read($b, 0, [int][Math]::Min($b.Length, $Count))
        if ($n -le 0) { throw (New-Object IO.EndOfStreamException) }
        $Count -= $n
    }
}

function Read-TarExe {
    # Streams a .tgz once, validates every entry path, and extracts ONLY opencode.exe to a file we name.
    # Returns @{Ok; Error; EntryName; Length}. No other archive content is ever written to disk.
    param([string]$TgzPath, [string]$OutFile)
    $exe = $script:Cfg.ExeName
    $fail = {
        param($m)
        try { if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force } } catch {}
        [pscustomobject]@{ Ok = $false; Error = $m; EntryName = $null; Length = 0 }
    }
    $fs = $null; $gz = $null
    try {
        $fs = [IO.File]::OpenRead($TgzPath)
        $sig = New-Object byte[] 2; [void]$fs.Read($sig, 0, 2)
        if ($sig[0] -ne 0x1F -or $sig[1] -ne 0x8B) { return & $fail 'The file is not a gzip archive (bad signature).' }
        [void]$fs.Seek(0, [IO.SeekOrigin]::Begin)
        Add-Type -AssemblyName System.IO.Compression
        $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
        $hdr = New-Object byte[] 512; $buf = New-Object byte[] 81920
        $longName = $null; $paxPath = $null; $found = $null
        while ($true) {
            $got = Read-Exact $gz $hdr 512
            if ($got -eq 0) { break }
            if ($got -lt 512) { return & $fail 'The archive is corrupt or incomplete.' }
            $zero = $true; for ($i = 0; $i -lt 512; $i++) { if ($hdr[$i] -ne 0) { $zero = $false; break } }
            if ($zero) { break }
            $name = [Text.Encoding]::UTF8.GetString($hdr, 0, 100).Split([char]0)[0]
            if ([Text.Encoding]::ASCII.GetString($hdr, 257, 5) -eq 'ustar') {
                $pre = [Text.Encoding]::UTF8.GetString($hdr, 345, 155).Split([char]0)[0]
                if ($pre) { $name = $pre + '/' + $name }
            }
            if ($hdr[124] -band 0x80) { return & $fail 'Unsupported archive size encoding.' }
            $szText = ([Text.Encoding]::ASCII.GetString($hdr, 124, 12)).Trim([char]0, ' ')
            $size = if ($szText) { [Convert]::ToInt64($szText, 8) } else { [long]0 }
            $type = [char]$hdr[156]
            $pad = (512 - ($size % 512)) % 512
            if ($type -eq 'L' -or $type -eq 'x') {
                if ($size -gt 65536) { return & $fail 'Unexpected archive header size.' }
                $meta = New-Object byte[] ([int]$size)
                if ((Read-Exact $gz $meta ([int]$size)) -lt $size) { return & $fail 'The archive is corrupt or incomplete.' }
                Skip-Bytes $gz $pad
                $txt = [Text.Encoding]::UTF8.GetString($meta)
                if ($type -eq 'L') { $longName = $txt.Split([char]0)[0] }
                else { $pm = [regex]::Match($txt, '(?m)^\d+ path=(.+)$'); if ($pm.Success) { $paxPath = $pm.Groups[1].Value.TrimEnd("`r") } }
                continue
            }
            if ($type -eq 'g') { Skip-Bytes $gz ($size + $pad); continue }
            if ($paxPath) { $name = $paxPath; $paxPath = $null } elseif ($longName) { $name = $longName; $longName = $null }
            $norm = $name.Replace('\', '/')
            if ($norm.StartsWith('/') -or $norm -match '(^|/)\.\.(/|$)' -or $norm -match '^[A-Za-z]:') { return & $fail "Unsafe path inside archive: $name" }
            $leaf = $norm.Substring($norm.LastIndexOf('/') + 1)
            $isFile = ($type -eq '0' -or $type -eq [char]0)
            if ($isFile -and $leaf -ieq $exe) {
                if ($found) { return & $fail "The archive contains several copies of $exe; refusing to guess." }
                if ($size -lt $script:Cfg.MinExeBytes) { return & $fail ("{0} in the archive is only {1} bytes - this does not look like a real build." -f $exe, $size) }
                if ($size -gt $script:Cfg.MaxExeBytes) { return & $fail "$exe in the archive is unreasonably large." }
                $out = [IO.File]::Create($OutFile)
                try {
                    $left = $size
                    while ($left -gt 0) {
                        $n = $gz.Read($buf, 0, [int][Math]::Min($buf.Length, $left))
                        if ($n -le 0) { throw (New-Object IO.EndOfStreamException) }
                        $out.Write($buf, 0, $n); $left -= $n
                    }
                } finally { $out.Dispose() }
                Skip-Bytes $gz $pad
                $found = [pscustomobject]@{ Ok = $true; Error = $null; EntryName = $norm; Length = $size }
            } else { Skip-Bytes $gz ($size + $pad) }
        }
        if (-not $found) { return & $fail "The archive does not contain $exe." }
        return $found
    } catch [IO.InvalidDataException] { return & $fail 'The archive is corrupt or incomplete.' }
    catch [IO.EndOfStreamException] { return & $fail 'The archive is corrupt or incomplete.' }
    catch { return & $fail ('Could not read the archive: ' + $_.Exception.Message) }
    finally { if ($gz) { $gz.Dispose() }; if ($fs) { $fs.Dispose() } }
}

# ==============================================================================
# 6. INSTALL ENGINE  (no UI; reports through callbacks)
# ==============================================================================
function Remove-WorkDir {
    param([string]$Dir)
    try {
        if (-not $Dir) { return }
        $tmp = [IO.Path]::GetTempPath()
        $leaf = [IO.Path]::GetFileName($Dir.TrimEnd('\', '/'))
        # Safety: only ever delete our own, freshly created staging folder inside the temp directory.
        if ($Dir.StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase) -and $leaf.StartsWith('OpenCodeCLISetup-') -and (Test-Path -LiteralPath $Dir)) {
            Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Invoke-InstallCore {
    param([string]$DestDir, $Release, [scriptblock]$Log, [scriptblock]$OnProgress)
    $c = $script:Cfg
    $res = [pscustomobject]@{ Success = $false; Version = $null; ExePath = $null; Previous = $null; Error = $null; Diag = $null }
    $diag = New-Object System.Collections.ArrayList
    $work = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'OpenCodeCLISetup-' + [guid]::NewGuid().ToString('N'))
    $destExe = [IO.Path]::Combine($DestDir, $c.ExeName)
    $newExe = $destExe + '.new'; $bakExe = $destExe + '.bak'
    $createdDir = $false; $hadOld = $false; $swapped = $false
    $say = { param($lvl, $msg) if ($Log) { & $Log $lvl $msg } }
    try {
        [void][IO.Directory]::CreateDirectory($work)
        $kind = [string](Get-Prop $Release 'Kind' 'zip')
        $zip = [IO.Path]::Combine($work, $(if ($kind -eq 'tgz') { 'package.tgz' } else { 'package.zip' })); $stage = [IO.Path]::Combine($work, $c.ExeName)
        [void]$diag.Add("Source: $($Release.Url)"); [void]$diag.Add("Destination: $DestDir")

        & $say 'info' 'Downloading the package'
        $dl = Save-Download -Url $Release.Url -OutFile $zip -OnProgress $OnProgress
        [void]$diag.Add("Final URL: $($dl.FinalUrl)"); [void]$diag.Add("Bytes: $($dl.Bytes)")
        & $say 'ok' ('Downloaded {0}' -f (Format-Size $dl.Bytes))

        $sha256 = Get-Prop $Release 'Sha256' $null; $integrity = [string](Get-Prop $Release 'Integrity' '')
        if ($sha256) {
            $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $sha256) { throw "Checksum mismatch. Expected $sha256 but got $actual." }
            & $say 'ok' 'SHA-256 checksum matches the published value'
        } elseif ($integrity -match '^sha512-(.+)$') {
            $h = [Security.Cryptography.SHA512]::Create(); $fsr = [IO.File]::OpenRead($zip)
            try { $actual = [Convert]::ToBase64String($h.ComputeHash($fsr)) } finally { $fsr.Dispose(); $h.Dispose() }
            if ($actual -ne $Matches[1]) { throw 'Integrity check failed: the download does not match the checksum published by the registry.' }
            & $say 'ok' 'SHA-512 integrity matches the registry value'
        } else {
            & $say 'warn' 'No published checksum was available; relying on HTTPS and archive validation.'
        }

        if ($kind -eq 'tgz') {
            $pkg = Read-TarExe $zip $stage
            if (-not $pkg.Ok) { throw $pkg.Error }
            & $say 'ok' "Archive validated ($($pkg.EntryName), $(Format-Size $pkg.Length))"
        } else {
            $pkg = Test-ZipPackage $zip
            if (-not $pkg.Ok) { throw $pkg.Error }
            & $say 'ok' "Archive validated ($($pkg.EntryName), $(Format-Size $pkg.Length))"
            Expand-ZipEntry -ZipPath $zip -EntryName $pkg.EntryName -OutFile $stage
        }
        $peErr = Test-PeX64 $stage
        if ($peErr) { throw $peErr }
        $sv = Invoke-Exe $stage -TimeoutMs $c.InstallVerifyTimeoutMs
        # CLI 2's official registry package can exit successfully without emitting a
        # semver string on stdout/stderr. Its npm SHA-512 integrity and PE/archive
        # checks have already passed, so accept exit code 0 for this trusted package
        # and use the exact registry version selected by the user.
        if (-not $sv.Ok -and $kind -eq 'tgz' -and $null -ne $sv.ExitCode -and [int]$sv.ExitCode -eq 0 -and $integrity -match '^sha512-.+') {
            $sv.Ok = $true
            $sv.Version = [string](Get-Prop $Release 'Version' 'unknown')
            [void]$diag.Add("Version probe: executable returned exit code 0 but no recognizable semver; using verified registry version $($sv.Version).")
        }
        if (-not $sv.Ok) {
            [void]$diag.Add("Version probe exit code: $($sv.ExitCode)")
            if ($sv.Output) { [void]$diag.Add("Version probe stdout: $($sv.Output)") }
            if ($sv.Error) { [void]$diag.Add("Version probe stderr: $($sv.Error)") }
            throw ('The downloaded executable failed its --version check. ' + $(if ($sv.Error) { $sv.Error } else { "Exit code $($sv.ExitCode)." }))
        }
        & $say 'ok' "Downloaded executable verified (version $($sv.Version))"

        $wt = Test-DirWritable $DestDir
        if (-not $wt.Ok) { throw "Cannot write to the destination folder: $($wt.Error)" }
        $createdDir = $wt.Created
        if (Test-Path -LiteralPath $destExe -PathType Leaf) {
            $hadOld = $true
            $pv = Invoke-Exe $destExe -TimeoutMs 10000
            if ($pv.Version) { $res.Previous = $pv.Version }
        }

        Copy-Item -LiteralPath $stage -Destination $newExe -Force
        if (Test-Path -LiteralPath $bakExe) { Remove-Item -LiteralPath $bakExe -Force }
        if ($hadOld) {
            try { Move-Item -LiteralPath $destExe -Destination $bakExe -Force }
            catch { throw "Could not replace the existing $($c.ExeName). Close any running OpenCode sessions and try again. ($($_.Exception.Message))" }
        }
        Move-Item -LiteralPath $newExe -Destination $destExe -Force
        $swapped = $true

        $chk = Invoke-Exe $destExe -TimeoutMs $c.InstallVerifyTimeoutMs
        # Apply the same narrow CLI 2 fallback after the executable has been copied.
        if (-not $chk.Ok -and $kind -eq 'tgz' -and $null -ne $chk.ExitCode -and [int]$chk.ExitCode -eq 0 -and $integrity -match '^sha512-.+') {
            $chk.Ok = $true
            $chk.Version = [string](Get-Prop $Release 'Version' 'unknown')
        }
        if (-not $chk.Ok) {
            [void]$diag.Add("Installed version probe exit code: $($chk.ExitCode)")
            if ($chk.Output) { [void]$diag.Add("Installed version probe stdout: $($chk.Output)") }
            if ($chk.Error) { [void]$diag.Add("Installed version probe stderr: $($chk.Error)") }
            throw ('The installed executable failed "--version". ' + $chk.Error)
        }
        $res.Version = if ($chk.Version) { $chk.Version } else { [string](Get-Prop $Release 'Version' 'unknown') }
        $res.ExePath = $destExe
        & $say 'ok' "Installed and verified: opencode.exe --version -> $($chk.Version)"

        if ($hadOld -and (Test-Path -LiteralPath $bakExe)) { try { Remove-Item -LiteralPath $bakExe -Force } catch {} }
        $marker = [ordered]@{ Tool = 'OpenCode-CLI-Setup'; ExePath = $destExe; Version = $chk.Version; InstalledUtc = (Get-Date).ToUniversalTime().ToString('o'); PathAdded = $false }
        [IO.File]::WriteAllText((Get-MarkerPath $DestDir), ($marker | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
        Add-KnownDir $DestDir
        $res.Success = $true
    } catch {
        $res.Error = $_.Exception.Message
        [void]$diag.Add("Error: $($res.Error)"); [void]$diag.Add($_.ScriptStackTrace)
        try {   # roll back so a failed update never leaves a broken executable behind
            if ($swapped -and (Test-Path -LiteralPath $destExe)) { Remove-Item -LiteralPath $destExe -Force }
            if ($hadOld -and -not (Test-Path -LiteralPath $destExe) -and (Test-Path -LiteralPath $bakExe)) { Move-Item -LiteralPath $bakExe -Destination $destExe -Force; [void]$diag.Add('Previous executable restored.') }
            if (Test-Path -LiteralPath $newExe) { Remove-Item -LiteralPath $newExe -Force }
            if ($createdDir -and -not $hadOld) { try { [IO.Directory]::Delete($DestDir) } catch {} }
        } catch { [void]$diag.Add('Rollback problem: ' + $_.Exception.Message) }
        try {
            $dp = [IO.Path]::Combine([IO.Path]::GetTempPath(), ('OpenCode-CLI-Setup-diagnostics-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
            [IO.File]::WriteAllLines($dp, [string[]]@($diag)); $res.Diag = $dp
        } catch {}
    } finally { Remove-WorkDir $work }
    return $res
}

# --- optional PATH integration (user scope, registry, explicit consent only) ---
function Get-UserPathRaw {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $k) { return '' }
    try { return [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
}
function Set-UserPathRaw {
    param([string]$Value)
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try { $k.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) } finally { $k.Close() }
    try {
        if (-not ('OcSetup.Env' -as [type])) {
            Add-Type -Namespace OcSetup -Name Env -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, UIntPtr w, string l, uint f, uint t, out UIntPtr r);
'@
        }
        $r = [UIntPtr]::Zero
        [void][OcSetup.Env]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 3000, [ref]$r)
    } catch {}
}
function Test-PathEntryMatch { param([string]$Entry, [string]$Dir) ([Environment]::ExpandEnvironmentVariables($Entry.Trim().Trim('"'))).TrimEnd('\') -ieq $Dir.TrimEnd('\') }
function Test-InUserPath { param([string]$Dir) foreach ($e in ((Get-UserPathRaw) -split ';')) { if ($e -and (Test-PathEntryMatch $e $Dir)) { return $true } } return $false }
function Add-UserPath {
    param([string]$Dir)
    $parts = @((Get-UserPathRaw) -split ';' | Where-Object { $_ })
    if (-not (@($parts | Where-Object { Test-PathEntryMatch $_ $Dir }).Count)) { Set-UserPathRaw (($parts + $Dir) -join ';') }
}
function Remove-UserPath {
    param([string]$Dir)
    $parts = @((Get-UserPathRaw) -split ';' | Where-Object { $_ -and -not (Test-PathEntryMatch $_ $Dir) })
    Set-UserPathRaw ($parts -join ';')
}
function Set-MarkerPathAdded {
    param([string]$Dir)
    try {
        $mp = Get-MarkerPath $Dir
        $m = Get-Content -LiteralPath $mp -Raw -Encoding UTF8 | ConvertFrom-Json
        $m.PathAdded = $true
        [IO.File]::WriteAllText($mp, ($m | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    } catch {}
}

# ==============================================================================
# 7. UNINSTALL ENGINE
# ==============================================================================
function Test-UninstallTarget {
    # Safety gate. Returns @{Ok; Error; Item}
    param([string]$ExePath, [string]$Source = 'custom')
    $bad = { param($m) [pscustomobject]@{ Ok = $false; Error = $m; Item = $null } }
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { return & $bad 'That file does not exist.' }
    $full = (Get-Item -LiteralPath $ExePath -Force).FullName
    if (([IO.Path]::GetFileName($full)) -ine $script:Cfg.ExeName) { return & $bad "Only $($script:Cfg.ExeName) can be removed by this tool." }
    if (Test-IsDesktopApp $full) { return & $bad 'This looks like the OpenCode Desktop application. This tool never touches Desktop files.' }
    return [pscustomobject]@{ Ok = $true; Error = $null; Item = (New-InstallItem -ExePath $full -Source $Source) }
}

function Invoke-UninstallCore {
    # Deletes ONLY: opencode.exe (+ our marker, + .bak/.new leftovers, + the folder if it is then empty).
    param($Item)
    $deleted = New-Object System.Collections.ArrayList
    $dir = $Item.Dir
    Remove-Item -LiteralPath $Item.Path -Force
    [void]$deleted.Add($Item.Path)
    foreach ($extra in @(($Item.Path + '.bak'), ($Item.Path + '.new'))) {
        if (Test-Path -LiteralPath $extra -PathType Leaf) { Remove-Item -LiteralPath $extra -Force; [void]$deleted.Add($extra) }
    }
    $mp = Get-MarkerPath $dir
    if ($Item.Owned -and (Test-Path -LiteralPath $mp -PathType Leaf)) { Remove-Item -LiteralPath $mp -Force; [void]$deleted.Add($mp) }
    $removedDir = $false
    try {
        if (@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop).Count -eq 0) { [IO.Directory]::Delete($dir); $removedDir = $true; [void]$deleted.Add($dir + '  (empty folder)') }
    } catch {}
    Remove-KnownDir $dir
    [pscustomobject]@{ Deleted = @($deleted); RemovedDir = $removedDir }
}

# ==============================================================================
# 8. UI FLOWS
# ==============================================================================
function Show-Error { param([string]$Title, [string]$Message, [string]$Hint = '') New-Ops; NL; Panel-Top $Title; Panel-Row $Message, 'red'; if ($Hint) { Panel-Row $Hint, 'dim' }; Panel-End; Write-Ops }

function Read-InstallFolder {
    # returns a normalised path or $null (cancel)
    while ($true) {
        $raw = Read-Line 'Install folder (Enter to cancel): '
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $r = ConvertTo-InstallPath $raw
        if ($r.Ok) { return $r.Path }
        Write-Status 'err' $r.Error
    }
}

function Show-InstallFlow {
    Show-SubHeader 'Install / Update'
    New-Ops
    Panel-Top 'WHERE TO INSTALL'
    Panel-Row ' 1 ', 'cyan', '  Default location (Recommended)', 'white'
    Panel-Row ('       ' + $script:Cfg.DefaultDir), 'text'
    Panel-Row '       Installer default - not a Windows requirement.', 'dim'
    Panel-Blank
    Panel-Row ' 2 ', 'purple', '  Custom location', 'white'
    Panel-Row '       Any local folder; paths with spaces and quotes are fine.', 'dim'
    Panel-Blank
    Panel-Row ' 3 ', 'dim', '  Back to main menu', 'white'
    Panel-End; Write-Ops
    $c = Read-Choice '123B' 'Select an option [1-3]:'
    if ($c -in @('3', 'B', $null)) { return }

    if ($c -eq '1') {
        $r = ConvertTo-InstallPath $script:Cfg.DefaultDir
        if (-not $r.Ok) { Show-Error 'INVALID DEFAULT FOLDER' $r.Error; Wait-Key; return }
        $dest = $r.Path
    } else {
        $dest = Read-InstallFolder
        if (-not $dest) { return }
    }

    Write-Status 'info' 'Looking up the official stable releases...'
    try { $cat = Get-ReleaseCatalog } catch { Show-Error 'RELEASE LOOKUP FAILED' $_.Exception.Message; Wait-Key; return }
    $entries = @($cat.Entries | Select-Object -First 9)
    if ($entries.Count -eq 0) { Show-Error 'NO RELEASES FOUND' 'Could not read the list of stable releases.' ($cat.Notes -join ' '); Wait-Key; return }
    New-Ops; NL
    Panel-Top 'CHOOSE A VERSION'
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        $tag = ''
        if ($e.Latest) { $tag = if ($e.Line -eq 2) { '   latest stable (recommended)' } else { '   latest of CLI 1' } }
        Panel-Row (' {0} ' -f ($i + 1)), $(if ($e.Line -eq 2) { 'cyan' } else { 'purple' }), ('  CLI {0} - {1}' -f $e.Line, $e.Version), 'white', $tag, 'green'
    }
    Panel-Blank
    Panel-Row ' B ', 'dim', '  Back', 'white'
    Panel-Blank
    Panel-Row 'Only stable releases are listed.', 'dim'
    Panel-Row 'CLI 1 comes from GitHub releases; CLI 2 comes from the npm registry.', 'dim'
    foreach ($n in $cat.Notes) { Panel-Row $n, 'yellow' }
    Panel-End; Write-Ops
    $valid = 'B'; for ($i = 1; $i -le $entries.Count; $i++) { $valid += [string]$i }
    $pick = Read-Choice $valid 'Select a version [Enter = 1]:' '1'
    if ($pick -in @('B', $null)) { return }
    Write-Status 'info' 'Preparing the download...'
    try { $rel = Resolve-Release $entries[[int]$pick - 1] } catch { Show-Error 'RELEASE LOOKUP FAILED' $_.Exception.Message; Wait-Key; return }

    # inspect destination before touching anything
    $destExe = [IO.Path]::Combine($dest, $script:Cfg.ExeName)
    $existing = 'None - this will be a new installation'; $existColor = 'green'
    if (Test-Path -LiteralPath $destExe -PathType Leaf) {
        $ex = Get-ExeVersionCached $destExe
        $owned = [bool](Read-Marker $destExe)
        $existing = 'Existing opencode.exe ' + $(if ($ex.Version) { "(v$($ex.Version)) " } else { '(version unknown) ' }) + 'will be REPLACED'
        if (-not $owned) { $existing += ' - not created by this installer' }
        $existColor = 'yellow'
    } elseif (Test-Path -LiteralPath $dest -PathType Container) { $existing = 'Folder exists; no opencode.exe inside yet'; $existColor = 'green' }

    New-Ops; NL
    Panel-Top 'REVIEW'
    Panel-Row 'Destination  ', 'dim', $dest, 'white'
    Panel-Row 'Existing     ', 'dim', $existing, $existColor
    Panel-Row 'Version      ', 'dim', $rel.Display, 'white'
    Panel-Row 'Build        ', 'dim', $rel.Variant, 'text'
    Panel-Row 'Source       ', 'dim', $rel.Url, 'text'
    if ($rel.Note) { Panel-Row $rel.Note, 'yellow' }
    Panel-Row 'PATH and OpenCode Desktop are not modified. You choose PATH afterwards.', 'dim'
    Panel-End; Write-Ops
    if (-not (Read-YesNo 'Proceed with the installation?' $true)) { Write-Status 'info' 'Cancelled. Nothing was changed.'; Wait-Key; return }

    New-Ops; NL; Write-Ops
    $log = { param($lvl, $msg) Write-Status $lvl $msg }
    $prog = { param($d, $t) Show-Progress $d $t }
    $res = Invoke-InstallCore -DestDir $dest -Release $rel -Log $log -OnProgress $prog

    if ($res.Success) {
        New-Ops; NL
        Panel-Top 'INSTALLATION COMPLETE'
        Panel-Row ($script:Ic.ok + ' '), 'green', ('OpenCode CLI v' + $res.Version + $(if ($res.Previous) { " (was v$($res.Previous))" } else { '' })), 'white'
        Panel-Row '  ', 'text', $res.ExePath, 'dim'
        Panel-End; Write-Ops
        try {
            if (-not (Test-InUserPath $dest)) {
                if (Read-YesNo 'Add this folder to your user PATH so "opencode" works anywhere?' $false) {
                    Add-UserPath $dest; Set-MarkerPathAdded $dest
                    Write-Status 'ok' 'Added to your user PATH. Open a NEW terminal window to use it.'
                } else { Write-Status 'info' "PATH unchanged. Run it with the full path: `"$($res.ExePath)`"" }
            } else { Write-Status 'info' 'This folder is already on your user PATH.' }
        } catch { Write-Status 'warn' ('PATH was not changed: ' + $_.Exception.Message) }
    } else {
        Show-Error 'INSTALLATION FAILED' $res.Error 'Your previous installation (if any) was left intact.'
        if ($res.Diag) { Write-Status 'info' ('Diagnostics saved to ' + $res.Diag) }
    }
    $script:Scan = Update-Scan
    Wait-Key
}

function Invoke-DeepScanUI {
    New-Ops; NL; Write-Ops
    Write-Status 'info' 'Searching all drives for OpenCode CLI. This can take a minute...'
    $cb = { param($root, $sec) New-Ops; T "`r" 'text'; Add-Erase; T ('  Scanning ' + $root + '   ' + $sec + ' s') 'dim'; Write-Ops }
    $script:Scan = Find-DeepInstallations -Existing $script:Scan -OnProgress $cb
    New-Ops; T "`r" 'text'; Add-Erase; Write-Ops
    Write-Status 'ok' ('Search finished: {0} copy/copies found.' -f @($script:Scan.Items).Count)
}

function Show-UninstallFlow {
    $item = $null
    while (-not $item) {
        Show-SubHeader 'Uninstall'
        $items = @($script:Scan.Items)
        New-Ops
        Panel-Top 'INSTALLED COPIES'
        if ($items.Count -eq 0) { Panel-Row 'No copy found yet. Press S to search all drives.', 'yellow' }
        for ($i = 0; $i -lt $items.Count; $i++) {
            $it = $items[$i]
            $ver = if ($it.Version) { 'v' + $it.Version } else { 'version unknown' }
            Panel-Row (' {0,2} ' -f ($i + 1)), 'cyan', ('  ' + $ver), 'white', ('  [' + $it.Source + ']'), 'dim'
            Panel-Row ('        ' + $it.Path), 'dim'
        }
        Panel-Blank
        Panel-Row '  S ', 'purple', '  Search all drives for more copies', 'white'
        Panel-Row '  B ', 'dim', '  Back', 'white'
        Panel-End; Write-Ops
        $in = Read-Line 'Type a number, S or B, then press Enter: '
        if ($null -eq $in) { return }
        $in = $in.Trim().ToUpperInvariant()
        if ($in -eq 'B' -or $in -eq '') { return }
        if ($in -eq 'S') { Invoke-DeepScanUI; continue }
        $n = 0
        if ([int]::TryParse($in, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) { $item = $items[$n - 1] }
        else { Write-Status 'err' 'Please type one of the numbers shown.'; Wait-Key }
    }

    if ($item.Manager) {
        Show-Error 'USE ITS OWN UNINSTALLER' ("This copy belongs to $($item.Manager).") ("Remove it with $($item.Manager) so nothing is left half-installed.")
        Wait-Key; return
    }

    New-Ops; NL
    Panel-Top 'DELETE THIS COPY?'
    Panel-Row 'File     ', 'dim', $item.Path, 'white'
    Panel-Row 'Version  ', 'dim', $(if ($item.Version) { $item.Version } else { 'unknown' }), 'text'
    if (-not $item.Owned) { Panel-Row 'Not installed by this tool. Only opencode.exe will be deleted.', 'yellow' }
    Panel-Row 'Your projects, settings and OpenCode Desktop are not touched.', 'dim'
    Panel-End; Write-Ops
    if (-not (Read-YesNo 'Delete it?' $false)) { Write-Status 'info' 'Cancelled. Nothing was deleted.'; Wait-Key; return }

    try {
        $r = Invoke-UninstallCore $item
        Write-Status 'ok' 'OpenCode CLI was removed.'
        if ($item.Owned -and $item.Marker -and $item.Marker.PathAdded) {
            try { Remove-UserPath $item.Dir; Write-Status 'ok' 'Also removed it from your user PATH (this tool had added it).' } catch {}
        }
    } catch {
        Show-Error 'COULD NOT DELETE' $_.Exception.Message 'If OpenCode is running, close it and try again.'
    }
    $script:Scan = Update-Scan
    Wait-Key
}

# ==============================================================================
# 9. ENTRY POINT
# ==============================================================================
$script:ExitCode = 0
$script:Scan = $null

function Start-App {
    try {
        if ($env:OS -ne 'Windows_NT') { throw 'OpenCode CLI Setup only runs on Windows.' }
        if (-not [Environment]::Is64BitOperatingSystem) { throw 'A 64-bit (x64) version of Windows is required.' }
        Initialize-Terminal
        $script:Scan = Find-Installations
        while ($true) {
            Show-MainScreen $script:Scan
            $c = Read-Choice '1234' 'Select an option [1-4]:'
            if ($null -eq $c -or $c -eq '4') { break }
            try {
                if ($c -eq '1') { Show-InstallFlow } elseif ($c -eq '2') { Show-UninstallFlow } elseif ($c -eq '3') { Invoke-DeepScanUI }
            } catch {
                Show-Error 'UNEXPECTED ERROR' $_.Exception.Message 'The application is still running; returning to the menu.'
                Wait-Key
            }
        }
    } catch {
        $script:ExitCode = 1
        Restore-Terminal
        Write-Host ''
        Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host ''
        try { [void][Console]::ReadKey($true) } catch {}
    } finally {
        Restore-Terminal
    }
    if ($script:ExitCode -eq 0) { Write-Host ("{0} - by {1}" -f $script:Cfg.Title, $script:Cfg.Author) }
}

if (-not $env:OPENCODE_SETUP_NOMAIN) {
    Start-App
    exit $script:ExitCode
}
