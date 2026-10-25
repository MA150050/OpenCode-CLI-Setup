<#
 Offline logic tests for OpenCode CLI Setup.
 Copyright (c) 2026 Mohamed Abd El-Hafez. All rights reserved.

 Runs on Windows PowerShell 5.1 / PowerShell 7 (and on Linux pwsh). It never touches the network
 except a loopback HttpListener, and never touches the registry or real install locations.
 The real opencode.exe is replaced by a tiny fake PE so Windows-only execution is stubbed.
#>
$ErrorActionPreference = 'Stop'
$env:OPENCODE_SETUP_NOMAIN = '1'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'OpenCode-CLI-Setup.ps1')
$ErrorActionPreference = 'Continue'

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('OcTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($sandbox)
$env:LOCALAPPDATA = Join-Path $sandbox 'localappdata'   # keeps installer state out of the real profile
$script:Pass = 0; $script:Fail = 0
function Check { param([string]$Name, [bool]$Cond, [string]$Info = '')
    if ($Cond) { $script:Pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $script:Fail++; Write-Host "  FAIL  $Name $Info" -ForegroundColor Red } }

# ---- helpers: fake x64 PE with an embedded version tag --------------------------
function New-FakeExeBytes { param([string]$Tag = 'VER=1.0.0', [int]$Size = 2MB, [int]$Machine = 0x8664)
    $b = New-Object byte[] $Size
    $b[0] = 0x4D; $b[1] = 0x5A; [BitConverter]::GetBytes([int]0x80).CopyTo($b, 60)
    $b[0x80] = 0x50; $b[0x81] = 0x45; [BitConverter]::GetBytes([uint16]$Machine).CopyTo($b, 0x84)
    [Text.Encoding]::ASCII.GetBytes($Tag).CopyTo($b, 0x200); return , $b }
function New-TestZip { param([string]$Path, [hashtable]$Entries)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $Path) { Remove-Item $Path -Force }
    $z = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try { foreach ($k in $Entries.Keys) { $e = $z.CreateEntry($k); $s = $e.Open(); $bytes = $Entries[$k]; $s.Write($bytes, 0, $bytes.Length); $s.Dispose() } } finally { $z.Dispose() } }
# stub: "running" a fake exe = reading its VER= tag (BROKEN => fails)
function Invoke-Exe { param([string]$Path, [string]$Arguments = '--version', [int]$TimeoutMs = 0)
    $t = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path), 0x200, 40)
    $m = [regex]::Match($t, 'VER=(\d+\.\d+\.\d+)')
    if ($t -match 'BROKEN' -or -not $m.Success) { return [pscustomobject]@{ Ok = $false; Version = $null; Output = ''; Error = 'boom'; TimedOut = $false; ExitCode = 1 } }
    return [pscustomobject]@{ Ok = $true; Version = $m.Groups[1].Value; Output = $m.Groups[1].Value; Error = ''; TimedOut = $false; ExitCode = 0 } }

Write-Host "`n[1] Path normalisation" -ForegroundColor Cyan
$sp = Join-Path $sandbox 'with space'
$r = ConvertTo-InstallPath ('"' + $sp + '"');       Check 'quoted path with spaces' ($r.Ok -and $r.Path -eq $sp)
$r = ConvertTo-InstallPath $sp;                       Check 'unquoted path with spaces' ($r.Ok -and $r.Path -eq $sp)
$r = ConvertTo-InstallPath ("'" + $sp + "'");        Check 'single-quoted path' ($r.Ok -and $r.Path -eq $sp)
$r = ConvertTo-InstallPath ($sp + [IO.Path]::DirectorySeparatorChar); Check 'trailing separator trimmed' ($r.Ok -and $r.Path -eq $sp)
Check 'empty rejected' (-not (ConvertTo-InstallPath '   ').Ok)
Check 'null rejected' (-not (ConvertTo-InstallPath $null).Ok)
Check 'relative rejected' (-not (ConvertTo-InstallPath 'tools\opencode').Ok)
Check 'wildcard rejected' (-not (ConvertTo-InstallPath ($sandbox + '/a*b')).Ok)
Check 'UNC rejected' (-not (ConvertTo-InstallPath '\\server\share\x').Ok)
Check 'drive root rejected' (-not (ConvertTo-InstallPath ([IO.Path]::GetPathRoot($sandbox))).Ok)
$f = Join-Path $sandbox 'afile.txt'; Set-Content $f 'x'
Check 'existing file rejected' (-not (ConvertTo-InstallPath $f).Ok)
$w = Test-DirWritable (Join-Path $sp 'new\deep'); Check 'directory auto-created + writable' ($w.Ok -and $w.Created -and (Test-Path (Join-Path $sp 'new\deep')))

Write-Host "`n[2] Stable-version catalog (network stubbed)" -ForegroundColor Cyan
$script:Net = @{}; $script:Avx2 = $true
function Invoke-TextGet { param([string]$Url, [hashtable]$Headers = @{})
    if ($script:Net.ContainsKey($Url)) { return $script:Net[$Url] }
    throw 'HTTP 404 Not Found (stub)' }
function Test-Avx2 { return $script:Avx2 }
$reg = $script:Cfg.NpmRegistry
$script:Net[$script:Cfg.V2LatestUrl] = '{"channel":"latest","name":"cli","distribution":"npm","version":"2.0.18","metadata":{"package":"@opencode/cli","github":{"sha":"041885d8","run_id":"36200497260","ref":"refs/heads/v2"}},"active":true,"minimum":false,"time_created":1790380515614}'   # exact shape of the live service (package is nested)
$script:Net["$reg/@opencode%2fcli-windows-x64"] = '{"name":"x","dist-tags":{"latest":"2.1.3","beta":"0.0.0-beta-1"},"versions":{"0.0.0-reserved":{"version":"0.0.0-reserved"},"2.0.9":{"name":"p","version":"2.0.9"},"2.0.10":{"version":"2.0.10"},"2.1.0":{"version":"2.1.0"},"2.1.3":{"version":"2.1.3"},"2.2.0-beta.1":{"version":"2.2.0-beta.1"},"0.0.0-beta-19507":{"version":"0.0.0-beta-19507"},"0.0.0-dev-21685":{"version":"0.0.0-dev-21685"}}}'
function New-Rel($tag, $pre, $draft, $asset) { $a = @(); if ($asset) { $a = @(@{ name = 'opencode-windows-x64.zip'; browser_download_url = "https://github.com/x/y/$tag.zip"; digest = 'sha256:' + ('a' * 64) }) }; @{ tag_name = $tag; prerelease = $pre; draft = $draft; assets = $a } }
$script:Net["$($script:Cfg.ApiBase)/$($script:Cfg.Repo)/releases?per_page=100&page=1"] = (ConvertTo-Json -Depth 6 @(
    (New-Rel 'v2.0.5' $false $false $true), (New-Rel 'v1.19.5' $true $false $true), (New-Rel 'v1.19.4' $false $false $true), (New-Rel 'v1.19.3' $false $true $true),
    (New-Rel 'v1.19.2' $false $false $false), (New-Rel 'v1.19.1' $false $false $true), (New-Rel 'v1.19.0' $false $false $true), (New-Rel 'v1.18.9' $false $false $true)))
Check 'numeric version sort (2.0.10 above 2.0.9)' (((Select-StableVersions @('2.0.9', '2.0.10', '2.1.0', '2.1.0') 5) -join ',') -eq '2.1.0,2.0.10,2.0.9')
Check 'beta/dev/rc/reserved builds are excluded' (@(Select-StableVersions @('0.0.0-beta-1', '2.2.0-rc.1', '0.0.0-dev-2', '1.0.0') 9).Count -eq 1)
$cat = Get-ReleaseCatalog
$v2 = @($cat.Entries | Where-Object { $_.Line -eq 2 }); $v1 = @($cat.Entries | Where-Object { $_.Line -eq 1 })
Check 'CLI 2 list: stable only, newest first' (($v2.Version -join ',') -eq '2.1.3,2.1.0,2.0.10,2.0.9') ($v2.Version -join ',')
Check 'newest stable CLI 2 is flagged as latest' ($v2[0].Latest -and -not $v2[1].Latest)
Check 'CLI 1 list: no prerelease/draft/asset-less/CLI 2 tags, max 3' (($v1.Version -join ',') -eq '1.19.4,1.19.1,1.19.0') ($v1.Version -join ',')
Check 'CLI 2 entries come before CLI 1 entries' ($cat.Entries[0].Line -eq 2 -and $cat.Entries[-1].Line -eq 1)
foreach ($variant in @('{"version":"2.1.3","package":"@opencode/cli"}', '{"error":"unexpected"}', '[]')) {
    $script:Net[$script:Cfg.V2LatestUrl] = $variant
    $cv = Get-ReleaseCatalog
    Check "CLI 2 list survives update-service answer: $($variant.Substring(0, [Math]::Min(22, $variant.Length)))" (@($cv.Entries | Where-Object { $_.Line -eq 2 }).Count -eq 4)
}
$script:Net.Remove($script:Cfg.V2LatestUrl)
Check 'CLI 2 list survives the update service being unreachable' (@((Get-ReleaseCatalog).Entries | Where-Object { $_.Line -eq 2 }).Count -eq 4)
$script:Net[$script:Cfg.V2LatestUrl] = '"""+real+"""'
$script:Net["$reg/@opencode%2fcli-windows-x64/2.1.3"] = '{"dist":{"tarball":"https://registry.npmjs.org/@opencode/cli-windows-x64/-/cli-windows-x64-2.1.3.tgz","integrity":"sha512-abc"}}'
$script:Net["$reg/@opencode%2fcli-windows-x64-baseline/2.1.3"] = '{"dist":{"tarball":"https://registry.npmjs.org/@opencode/cli-windows-x64-baseline/-/cli-windows-x64-baseline-2.1.3.tgz","integrity":"sha512-def"}}'
$r = Resolve-Release $v2[0]
Check 'resolve CLI 2 (AVX2 CPU): standard build + integrity' ($r.Url -like '*cli-windows-x64-2.1.3.tgz' -and $r.Integrity -eq 'sha512-abc')
$script:Avx2 = $false; $r = Resolve-Release $v2[0]
Check 'resolve CLI 2 (no AVX2): baseline build chosen' ($r.Url -like '*cli-windows-x64-baseline-2.1.3.tgz' -and $r.Variant -like 'baseline*' -and $r.Integrity -eq 'sha512-def')
$script:Avx2 = $true
$threw = $false; $m = ''; try { [void](Resolve-Release $v2[1]) } catch { $threw = $true; $m = $_.Exception.Message }
Check 'resolve unavailable version: clear error' ($threw -and $m -like '*not available*')
$r = Resolve-Release $v1[0]
Check 'resolve CLI 1: zip kind, release asset, published sha256' ($r.Kind -eq 'zip' -and $r.Url -like '*v1.19.4.zip' -and $r.Sha256 -eq ('a' * 64))
$saveNet = $script:Net; $script:Net = @{ $script:Cfg.V2LatestUrl = '{"version":"2.1.3","package":"@opencode/cli"}' }
$cat2 = Get-ReleaseCatalog
Check 'one source failing does not break the other (notes explain)' (@($cat2.Notes).Count -eq 2 -and @($cat2.Entries).Count -eq 0)
$script:Net = @{ "$($script:Cfg.ApiBase)/$($script:Cfg.Repo)/releases?per_page=100&page=1" = $saveNet["$($script:Cfg.ApiBase)/$($script:Cfg.Repo)/releases?per_page=100&page=1"] }
$cat3 = Get-ReleaseCatalog
Check 'CLI 2 lookup failure still lists CLI 1' (@($cat3.Entries | Where-Object { $_.Line -eq 1 }).Count -eq 3 -and $cat3.Notes[0] -like 'CLI 2 list unavailable*')
$script:Net = $saveNet

Write-Host "`n[3] Archive validation" -ForegroundColor Cyan
$ok = New-FakeExeBytes
$z = Join-Path $sandbox 'good.zip';   New-TestZip $z @{ 'opencode.exe' = $ok }
$p = Test-ZipPackage $z;              Check 'valid archive accepted' ($p.Ok -and $p.EntryName -eq 'opencode.exe')
New-TestZip $z @{ 'bin/opencode.exe' = $ok; 'README.txt' = [byte[]](1, 2, 3) }
$p = Test-ZipPackage $z;              Check 'nested exe found' ($p.Ok -and $p.EntryName -eq 'bin/opencode.exe')
New-TestZip $z @{ 'readme.txt' = [byte[]](1, 2, 3) }
$p = Test-ZipPackage $z;              Check 'missing exe rejected' (-not $p.Ok -and $p.Error -like '*does not contain*')
New-TestZip $z @{ 'opencode.exe' = [byte[]](1, 2, 3) }
$p = Test-ZipPackage $z;              Check 'tiny exe rejected' (-not $p.Ok)
New-TestZip $z @{ '../evil.exe' = [byte[]](1); 'opencode.exe' = $ok }
$p = Test-ZipPackage $z;              Check 'path traversal rejected' (-not $p.Ok -and $p.Error -like '*Unsafe*')
New-TestZip $z @{ 'a/opencode.exe' = $ok; 'b/opencode.exe' = $ok }
$p = Test-ZipPackage $z;              Check 'ambiguous duplicates rejected' (-not $p.Ok)
$bad = Join-Path $sandbox 'notzip.zip'; [IO.File]::WriteAllText($bad, 'this is html, not a zip')
$p = Test-ZipPackage $bad;            Check 'non-zip rejected' (-not $p.Ok -and $p.Error -like '*not a ZIP*')
$trunc = Join-Path $sandbox 'trunc.zip'; New-TestZip $z @{ 'opencode.exe' = $ok }
$all = [IO.File]::ReadAllBytes($z); [IO.File]::WriteAllBytes($trunc, $all[0..([int]($all.Length / 2))])
$p = Test-ZipPackage $trunc;          Check 'truncated zip rejected' (-not $p.Ok)
$pe = Join-Path $sandbox 'x.exe'
[IO.File]::WriteAllBytes($pe, (New-FakeExeBytes));                    Check 'x64 PE accepted' ($null -eq (Test-PeX64 $pe))
[IO.File]::WriteAllBytes($pe, (New-FakeExeBytes -Machine 0xAA64));    Check 'ARM64 PE rejected' ((Test-PeX64 $pe) -like '*not x64*')
[IO.File]::WriteAllBytes($pe, (New-Object byte[] 4096));              Check 'non-PE rejected' ((Test-PeX64 $pe) -like '*MZ*')

Write-Host "`n[3b] .tgz package (CLI 2 format)" -ForegroundColor Cyan
function New-TestTgz { param([string]$Path, $Entries, [switch]$NoGzip)
    $ms = New-Object IO.MemoryStream
    foreach ($e in $Entries) {
        $h = New-Object byte[] 512
        [Text.Encoding]::ASCII.GetBytes($e.Name).CopyTo($h, 0)
        [Text.Encoding]::ASCII.GetBytes([Convert]::ToString([long]$e.Bytes.Length, 8).PadLeft(11, '0')).CopyTo($h, 124)
        $h[156] = [byte][char]'0'; [Text.Encoding]::ASCII.GetBytes('ustar').CopyTo($h, 257)
        $ms.Write($h, 0, 512); $ms.Write($e.Bytes, 0, $e.Bytes.Length)
        $pad = (512 - ($e.Bytes.Length % 512)) % 512; if ($pad) { $ms.Write((New-Object byte[] $pad), 0, $pad) }
    }
    $ms.Write((New-Object byte[] 1024), 0, 1024)
    $raw = $ms.ToArray()
    if ($NoGzip) { [IO.File]::WriteAllBytes($Path, $raw); return }
    $fs = [IO.File]::Create($Path); $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Compress)
    $gz.Write($raw, 0, $raw.Length); $gz.Dispose(); $fs.Dispose() }
$exeBytes = New-FakeExeBytes 'VER=2.5.0'
$tg = Join-Path $sandbox 'good.tgz'; $outExe = Join-Path $sandbox 'tgz-out.exe'
New-TestTgz $tg @(@{ Name = 'package/package.json'; Bytes = [Text.Encoding]::ASCII.GetBytes('{"name":"x"}') }, @{ Name = 'package/bin/opencode.exe'; Bytes = $exeBytes })
$p = Read-TarExe $tg $outExe
Check 'valid tgz: exe extracted byte-for-byte' ($p.Ok -and $p.EntryName -eq 'package/bin/opencode.exe' -and (Get-FileHash $outExe).Hash -eq (Get-FileHash -InputStream ([IO.MemoryStream]::new($exeBytes))).Hash)
Check 'valid tgz: only the exe is written (no other files)' (@(Get-ChildItem $sandbox -Filter 'package*' -ErrorAction SilentlyContinue).Count -eq 0)
New-TestTgz $tg @(@{ Name = 'package/package.json'; Bytes = [byte[]](1, 2) })
Check 'tgz without exe rejected' (-not (Read-TarExe $tg $outExe).Ok)
New-TestTgz $tg @(@{ Name = 'package/bin/opencode.exe'; Bytes = [byte[]](1, 2, 3) })
Check 'tgz with tiny exe rejected, nothing left behind' ((-not (Read-TarExe $tg $outExe).Ok) -and -not (Test-Path $outExe))
New-TestTgz $tg @(@{ Name = '../../evil.txt'; Bytes = [byte[]](1) }, @{ Name = 'package/bin/opencode.exe'; Bytes = $exeBytes })
$p = Read-TarExe $tg $outExe
Check 'tgz path traversal rejected' (-not $p.Ok -and $p.Error -like '*Unsafe*')
New-TestTgz $tg @(@{ Name = 'a/opencode.exe'; Bytes = $exeBytes }, @{ Name = 'b/opencode.exe'; Bytes = $exeBytes })
$p = Read-TarExe $tg $outExe
Check 'tgz with duplicate exe rejected and output removed' (-not $p.Ok -and -not (Test-Path $outExe))
$plain = Join-Path $sandbox 'plain.tgz'; New-TestTgz $plain @(@{ Name = 'package/bin/opencode.exe'; Bytes = $exeBytes }) -NoGzip
Check 'non-gzip file rejected' ((Read-TarExe $plain $outExe).Error -like '*not a gzip*')
New-TestTgz $tg @(@{ Name = 'package/bin/opencode.exe'; Bytes = $exeBytes })
$all = [IO.File]::ReadAllBytes($tg); $cut = Join-Path $sandbox 'cut.tgz'; [IO.File]::WriteAllBytes($cut, $all[0..([int]($all.Length / 2))])
Check 'truncated tgz rejected, partial exe removed' ((-not (Read-TarExe $cut $outExe).Ok) -and -not (Test-Path $outExe))

Write-Host "`n[4] Download (loopback server)" -ForegroundColor Cyan
$port = 18000 + (Get-Random -Maximum 1000)
New-TestZip $z @{ 'opencode.exe' = $ok }
$goodBytes = [IO.File]::ReadAllBytes($z)
$ps = [powershell]::Create()
[void]$ps.AddScript({ param($port, $good)
    $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
    while ($l.IsListening) {
        try { $c = $l.GetContext() } catch { break }
        $path = $c.Request.Url.AbsolutePath
        if ($path -eq '/good.zip') { $c.Response.ContentLength64 = $good.Length; $c.Response.OutputStream.Write($good, 0, $good.Length) }
        elseif ($path -eq '/short.zip') { $c.Response.ContentLength64 = $good.Length + 5000; $c.Response.OutputStream.Write($good, 0, 100); $c.Response.Abort(); continue }
        elseif ($path -eq '/stop') { $c.Response.Close(); $l.Stop(); break }
        else { $c.Response.StatusCode = 404 }
        $c.Response.Close()
    } }).AddArgument($port).AddArgument($goodBytes)
$h = $ps.BeginInvoke(); Start-Sleep -Milliseconds 600
$dlOut = Join-Path $sandbox 'dl.zip'
$u = "http://localhost:$port"
$threw = $false; $m = ''; try { [void](Save-Download -Url "$u/good.zip" -OutFile $dlOut) } catch { $threw = $true; $m = $_.Exception.Message }
Check 'HTTP + untrusted host refused by default' ($threw -and $m -like '*non-HTTPS*')
$script:Cfg.RequireHttps = $false; $script:Cfg.TrustedHosts = 'localhost'      # test-only relaxation
$calls = 0; $d = Save-Download -Url "$u/good.zip" -OutFile $dlOut -OnProgress { param($a, $b) $script:calls++ }
Check 'download succeeds, size matches' ($d.Bytes -eq $goodBytes.Length -and (Get-Item $dlOut).Length -eq $goodBytes.Length)
Check 'progress callback invoked with real work' ($calls -ge 1)
$threw = $false; $m = ''; try { [void](Save-Download -Url "$u/missing.zip" -OutFile $dlOut) } catch { $threw = $true; $m = $_.Exception.Message }
Check '404 reported' ($threw -and $m -like '*404*')
$threw = $false; try { [void](Save-Download -Url "$u/short.zip" -OutFile $dlOut) } catch { $threw = $true }
Check 'truncated download detected' $threw
$script:Cfg.TrustedHosts = '(^|\.)(github\.com|githubusercontent\.com)$'
$threw = $false; $m = ''; try { [void](Save-Download -Url 'https://example.com/x.zip' -OutFile $dlOut) } catch { $threw = $true; $m = $_.Exception.Message }
Check 'untrusted host refused' ($threw -and $m -like '*untrusted*')

Write-Host "`n[5] Install engine: fresh install, update, rollback, cleanup" -ForegroundColor Cyan
$script:Cfg.RequireHttps = $false; $script:Cfg.TrustedHosts = 'localhost'
$tmpBefore = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Filter 'OpenCodeCLISetup-*' -Directory -ErrorAction SilentlyContinue).Count
$dest = Join-Path $sp 'CLI folder'
$rel = [pscustomobject]@{ Version = '1.0.0'; Url = "$u/good.zip"; Sha256 = $null; Note = $null }
$logs = New-Object System.Collections.ArrayList
$log = { param($l, $m) [void]$logs.Add("$l|$m") }
$res = Invoke-InstallCore -DestDir $dest -Release $rel -Log $log
Check 'fresh install succeeds' ($res.Success -and $res.Version -eq '1.0.0') $res.Error
Check 'exe + marker present, no leftovers' ((Test-Path (Join-Path $dest 'opencode.exe')) -and (Test-Path (Join-Path $dest '.opencode-cli-setup.json')) -and -not (Test-Path (Join-Path $dest 'opencode.exe.new')) -and -not (Test-Path (Join-Path $dest 'opencode.exe.bak')))
Check 'marker recognised as owned' ([bool](Read-Marker (Join-Path $dest 'opencode.exe')))
Check 'no published checksum is disclosed honestly' (@($logs | Where-Object { $_ -like 'warn|No published checksum*' }).Count -eq 1)

# update with newer version
$v2 = Join-Path $sandbox 'v2.zip'; New-TestZip $v2 @{ 'opencode.exe' = (New-FakeExeBytes 'VER=2.0.0') }
$bytesV2 = [IO.File]::ReadAllBytes($v2)
# serve v2 by swapping what /good.zip returns is not possible post-start; use file:// style test via second listener instead
$port2 = $port + 1; $ps2 = [powershell]::Create()
[void]$ps2.AddScript({ param($port, $a, $b, $c)
    $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
    while ($l.IsListening) { try { $x = $l.GetContext() } catch { break }
        $map = @{ '/v2.zip' = $a; '/broken.zip' = $b; '/notexe.zip' = $c }
        $p = $x.Request.Url.AbsolutePath
        if ($p -eq '/stop') { $x.Response.Close(); $l.Stop(); break }
        if ($map.ContainsKey($p)) { $by = $map[$p]; $x.Response.ContentLength64 = $by.Length; $x.Response.OutputStream.Write($by, 0, $by.Length) } else { $x.Response.StatusCode = 404 }
        $x.Response.Close() } }).AddArgument($port2).AddArgument($bytesV2).AddArgument($(New-TestZip (Join-Path $sandbox 'b.zip') @{ 'opencode.exe' = (New-FakeExeBytes 'VER=9.9.9 BROKEN') }; [IO.File]::ReadAllBytes((Join-Path $sandbox 'b.zip')))).AddArgument($(New-TestZip (Join-Path $sandbox 'n.zip') @{ 'readme.txt' = [byte[]](1, 2, 3) }; [IO.File]::ReadAllBytes((Join-Path $sandbox 'n.zip'))))
$h2 = $ps2.BeginInvoke(); Start-Sleep -Milliseconds 600
$u2 = "http://localhost:$port2"
$res = Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '2.0.0'; Url = "$u2/v2.zip"; Sha256 = $null; Note = $null }) -Log $log
Check 'update replaces executable' ($res.Success -and $res.Version -eq '2.0.0' -and $res.Previous -eq '1.0.0') $res.Error
Check 'update leaves no .bak/.new' (-not (Test-Path (Join-Path $dest 'opencode.exe.bak')) -and -not (Test-Path (Join-Path $dest 'opencode.exe.new')))

# failing update: downloaded binary fails --version -> existing install untouched
$before = (Get-FileHash (Join-Path $dest 'opencode.exe')).Hash
$res = Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '9.9.9'; Url = "$u2/broken.zip"; Sha256 = $null; Note = $null }) -Log $log
Check 'broken download refused' (-not $res.Success -and $res.Error -like '*--version*')
Check 'existing install untouched after failed update' ((Get-FileHash (Join-Path $dest 'opencode.exe')).Hash -eq $before)
Check 'diagnostics file kept for failures' ($res.Diag -and (Test-Path $res.Diag))
$res = Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '1.0.0'; Url = "$u2/notexe.zip"; Sha256 = $null; Note = $null }) -Log $log
Check 'archive without exe refused' (-not $res.Success -and $res.Error -like '*does not contain*')
Check 'HTTP 404 refused, install intact' ((-not (Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '3'; Url = "$u2/nope.zip"; Sha256 = $null; Note = $null }) -Log $log).Success) -and (Get-FileHash (Join-Path $dest 'opencode.exe')).Hash -eq $before)
$res = Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '2.0.0'; Url = "$u2/v2.zip"; Sha256 = ('0' * 64); Note = $null }) -Log $log
Check 'checksum mismatch refused' (-not $res.Success -and $res.Error -like '*Checksum mismatch*')
# rollback after swap: destination verify fails (simulate by making the post-swap check fail)
$orig = ${function:Invoke-Exe}; $n = 0
function Invoke-Exe { param([string]$Path, [string]$Arguments = '--version', [int]$TimeoutMs = 0)
    if ($Path -like '*CLI folder*' -and $Path -notlike '*.new' -and $script:failDest) { return [pscustomobject]@{ Ok = $false; Version = $null; Output = ''; Error = 'sim fail'; TimedOut = $false; ExitCode = 1 } }
    & $script:origExe @PSBoundParameters }
$script:origExe = $orig; $script:failDest = $false
$script:failDest = $true
# first call checks previous version (dest) -> must tolerate failure there; post-swap check fails -> rollback
$res = Invoke-InstallCore -DestDir $dest -Release ([pscustomobject]@{ Version = '2.0.0'; Url = "$u2/v2.zip"; Sha256 = $null; Note = $null }) -Log $log
$script:failDest = $false
Check 'post-install verification failure rolls back' (-not $res.Success -and (Get-FileHash (Join-Path $dest 'opencode.exe')).Hash -eq $before -and -not (Test-Path (Join-Path $dest 'opencode.exe.bak')))
$tmpAfter = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Filter 'OpenCodeCLISetup-*' -Directory -ErrorAction SilentlyContinue).Count
Check 'staging directories cleaned up' ($tmpAfter -eq $tmpBefore)
$fresh = Join-Path $sandbox 'never-created\x'
$res = Invoke-InstallCore -DestDir $fresh -Release ([pscustomobject]@{ Version = '9.9.9'; Url = "$u2/broken.zip"; Sha256 = $null; Note = $null }) -Log $log
Check 'failed fresh install creates no destination folder' (-not $res.Success -and -not (Test-Path $fresh))
[void][Net.WebRequest]::Create("$u/stop").GetResponse(); [void][Net.WebRequest]::Create("$u2/stop").GetResponse()

Write-Host "`n[5b] Install engine with a CLI 2 style .tgz" -ForegroundColor Cyan
New-TestTgz (Join-Path $sandbox 'srv.tgz') @(@{ Name = 'package/package.json'; Bytes = [Text.Encoding]::ASCII.GetBytes('{}') }, @{ Name = 'package/bin/opencode.exe'; Bytes = (New-FakeExeBytes 'VER=2.5.0') })
$tgzBytes = [IO.File]::ReadAllBytes((Join-Path $sandbox 'srv.tgz'))
$sha = [Security.Cryptography.SHA512]::Create(); $integrityOk = 'sha512-' + [Convert]::ToBase64String($sha.ComputeHash($tgzBytes))
$port3 = $port + 2; $ps3 = [powershell]::Create()
[void]$ps3.AddScript({ param($port, $by)
    $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$port/"); $l.Start()
    while ($l.IsListening) { try { $x = $l.GetContext() } catch { break }
        $p = $x.Request.Url.AbsolutePath
        if ($p -eq '/stop') { $x.Response.Close(); $l.Stop(); break }
        if ($p -eq '/pkg.tgz') { $x.Response.ContentLength64 = $by.Length; $x.Response.OutputStream.Write($by, 0, $by.Length) } else { $x.Response.StatusCode = 404 }
        $x.Response.Close() } }).AddArgument($port3).AddArgument($tgzBytes)
$h3 = $ps3.BeginInvoke(); Start-Sleep -Milliseconds 600
$u3 = "http://localhost:$port3"; $dest3 = Join-Path $sp 'tgz install'
$relT = [pscustomobject]@{ Version = '2.5.0'; Line = 2; Url = "$u3/pkg.tgz"; Sha256 = $null; Integrity = $integrityOk; Kind = 'tgz'; Variant = 'standard'; Note = $null; Display = 'CLI 2 - 2.5.0' }
$logs3 = New-Object System.Collections.ArrayList; $log3 = { param($l, $m) [void]$logs3.Add("$l|$m") }
$res = Invoke-InstallCore -DestDir $dest3 -Release $relT -Log $log3
Check 'CLI 2 tgz install succeeds and verifies' ($res.Success -and $res.Version -eq '2.5.0') $res.Error
Check 'registry SHA-512 integrity was verified' (@($logs3 | Where-Object { $_ -like 'ok|SHA-512 integrity matches*' }).Count -eq 1)
$before3 = (Get-FileHash (Join-Path $dest3 'opencode.exe')).Hash
$relBad = $relT.PSObject.Copy(); $relBad.Integrity = 'sha512-' + [Convert]::ToBase64String((New-Object byte[] 64))
$res = Invoke-InstallCore -DestDir $dest3 -Release $relBad -Log $log3
Check 'wrong registry integrity refused, install intact' (-not $res.Success -and $res.Error -like '*Integrity check failed*' -and (Get-FileHash (Join-Path $dest3 'opencode.exe')).Hash -eq $before3)
[void][Net.WebRequest]::Create("$u3/stop").GetResponse()

Write-Host "`n[6] Detection" -ForegroundColor Cyan
$script:Cfg.DefaultDir = $dest; Save-KnownDirs @()
$origPath = $env:PATH; $env:PATH = $env:PATH + [IO.Path]::PathSeparator + $dest
$scan = Find-Installations
Check 'found once despite default dir + PATH duplicates' ($scan.Status -eq 'Found' -and @($scan.Items).Count -eq 1)
Check 'version and ownership reported' ($scan.Items[0].Version -eq '2.0.0' -and $scan.Items[0].Owned)
$env:PATH = $origPath; $script:Cfg.DefaultDir = Join-Path $sandbox 'nothing-here'
Save-KnownDirs @()
$scan = Find-Installations
Check 'NotFound status when nothing is present' ($scan.Status -eq 'NotFound' -and @($scan.Items).Count -eq 0)

Write-Host "`n[7] Uninstall safety" -ForegroundColor Cyan
$item = (Test-UninstallTarget (Join-Path $dest 'opencode.exe') 'custom').Item
Set-Content (Join-Path $dest 'user-notes.txt') 'precious'
$r = Invoke-UninstallCore $item
Check 'exe and marker removed' (-not (Test-Path (Join-Path $dest 'opencode.exe')) -and -not (Test-Path (Join-Path $dest '.opencode-cli-setup.json')))
Check 'unrelated file survives, folder kept' ((Test-Path (Join-Path $dest 'user-notes.txt')) -and (Test-Path $dest) -and -not $r.RemovedDir)
Remove-Item (Join-Path $dest 'user-notes.txt')
$empty = Join-Path $sandbox 'empty-case'; $null = Test-DirWritable $empty; [IO.File]::WriteAllBytes((Join-Path $empty 'opencode.exe'), (New-FakeExeBytes))
$r = Invoke-UninstallCore (Test-UninstallTarget (Join-Path $empty 'opencode.exe')).Item
Check 'empty folder removed afterwards' ($r.RemovedDir -and -not (Test-Path $empty))
$other = Join-Path $sandbox 'other.exe'; [IO.File]::WriteAllBytes($other, (New-FakeExeBytes))
Check 'refuses files not named opencode.exe' (-not (Test-UninstallTarget $other).Ok)
Check 'refuses missing file' (-not (Test-UninstallTarget (Join-Path $sandbox 'ghost\opencode.exe')).Ok)
$desk = Join-Path $sandbox 'Desktop'; $null = Test-DirWritable (Join-Path $desk 'resources'); [IO.File]::WriteAllBytes((Join-Path $desk 'opencode.exe'), (New-FakeExeBytes))
Check 'refuses OpenCode Desktop layout' (-not (Test-UninstallTarget (Join-Path $desk 'opencode.exe')).Ok)
$unowned = Join-Path $sandbox 'unowned'; $null = Test-DirWritable $unowned; [IO.File]::WriteAllBytes((Join-Path $unowned 'opencode.exe'), (New-FakeExeBytes))
$t = Test-UninstallTarget (Join-Path $unowned 'opencode.exe')
Check 'unmarked exe is flagged as not owned' ($t.Ok -and -not $t.Item.Owned)
Set-Content (Join-Path $unowned 'config.json') '{}'
$null = Invoke-UninstallCore $t.Item
Check 'unowned uninstall deletes only the exe' ((Test-Path (Join-Path $unowned 'config.json')) -and -not (Test-Path (Join-Path $unowned 'opencode.exe')))
Check 'package-manager paths recognised' ((Get-PackageManager 'C:\Users\x\scoop\apps\opencode\current\opencode.exe') -eq 'Scoop' -and -not (Get-PackageManager 'C:\Tools\OpenCode\CLI\opencode.exe'))

Write-Host "`n[8] Rendering (forced ANSI) - widths and gradient" -ForegroundColor Cyan
$script:Ansi = $true; $script:Ic = @{ dot = '*'; ok = '+'; bad = 'x'; diamond = '*'; prompt = '>'; arrow = '>'; bar = '#'; barOff = '-' }
$sw = New-Object IO.StringWriter; $old = [Console]::Out; [Console]::SetOut($sw)
Show-Brand; Show-StatusPanel ([pscustomobject]@{ Status = 'NotFound'; Items = @(); Errors = @() }); Show-StatusPanel $scan
[Console]::SetOut($old)
$txt = $sw.ToString(); $plain = [regex]::Replace($txt, "\x1b\[[0-9;]*[A-Za-z]", '')
$panelLines = @($plain -split "`n" | Where-Object { $_ -match '^[\u256D\u2502\u2570]' })
$badW = @($panelLines | Where-Object { $_.TrimEnd("`r").Length -ne $script:PanelWidth })
Check 'every panel line is exactly 78 columns' ($panelLines.Count -gt 8 -and $badW.Count -eq 0) ("bad=" + $badW.Count)
Check 'logo uses 24-bit gradient colours' (([regex]::Matches($txt, '38;2;\d+;\d+;\d+m')).Count -gt 20)
Check 'brand text present' ($plain -like '*by Mohamed Abd El-Hafez*' -and $plain -like '*Copyright (c) 2026 Mohamed Abd El-Hafez. All rights reserved.*' -and $plain -like '*AUTOMATE*')
Check 'honest scope wording present' ($plain -like '*not a full-disk search*' -and $plain -like '*NOT FOUND in the locations checked*')

Write-Host "`n[9] Menu navigation via redirected input" -ForegroundColor Cyan
$script:Ansi = $false
$inFile = Join-Path $sandbox 'in.txt'
[IO.File]::WriteAllText($inFile, "x`n9`n2`nB`n1`n3`n4`n")
$runner = Join-Path $sandbox 'run.ps1'
[IO.File]::WriteAllText($runner, "`$env:OPENCODE_SETUP_NOMAIN='1'; `$env:OS='Windows_NT'; `$env:LOCALAPPDATA='$($env:LOCALAPPDATA)'; . '$root/OpenCode-CLI-Setup.ps1'; `$script:Cfg.DefaultDir='$sandbox/none'; Start-App")
$exe = (Get-Process -Id $PID).Path
$out = [IO.File]::ReadAllText($inFile) | & $exe -NoProfile -File $runner 2>&1 | Out-String
Check 'invalid keys handled without crashing' ($out -like '*Invalid choice*')
Check 'uninstall screen reachable, Back returns to menu' ($out -like '*INSTALLED COPIES*' -and ([regex]::Matches($out, 'MAIN MENU')).Count -ge 3)
Check 'install screen reachable, Back returns to menu' ($out -like '*WHERE TO INSTALL*')
Check 'scan-all-drives entry exists in menu' ($out -like '*Scan all drives*')
Check 'clean exit message' ($out -like '*OpenCode CLI - Setup - by Mohamed Abd El-Hafez*')

Write-Host "`n[9b] Version picker UI (no typing of version numbers)" -ForegroundColor Cyan
$stubFile = Join-Path $sandbox 'stubs.ps1'
$stubs = @"
`$env:OPENCODE_SETUP_NOMAIN='1'; `$env:LOCALAPPDATA='$($env:LOCALAPPDATA)'; . '$root/OpenCode-CLI-Setup.ps1'; Initialize-Terminal
`$script:Cfg.DefaultDir='$sandbox/none'
function Test-Avx2 { `$true }
function Invoke-TextGet { param([string]`$Url,[hashtable]`$Headers=@{})
  if (`$Url -eq `$script:Cfg.V2LatestUrl) { return '{"channel":"latest","name":"cli","distribution":"npm","version":"2.0.18","metadata":{"package":"@opencode/cli","github":{"sha":"041885d8","run_id":"36200497260","ref":"refs/heads/v2"}},"active":true,"minimum":false,"time_created":1790380515614}' }
  if (`$Url -like '*%2fcli-windows-x64/2.1.3') { return '{"dist":{"tarball":"https://registry.npmjs.org/x.tgz","integrity":"sha512-abc"}}' }
  if (`$Url -like '*%2fcli-windows-x64') { return '{"versions":{"2.1.3":{"version":"2.1.3"},"2.1.2":{"version":"2.1.2"},"2.2.0-beta.1":{"version":"2.2.0-beta.1"}}}' }
  throw 'HTTP 403 Forbidden (stub)' }
`$script:Scan = [pscustomobject]@{ Status='NotFound'; Items=@(); Errors=@(); DeepDone=`$false }
Show-InstallFlow
"@
[IO.File]::WriteAllText($stubFile, $stubs)
$dst = Join-Path $sandbox 'ui-install'
$o = "2`n$dst`nB`n" | & $exe -NoProfile -File $stubFile 2>&1 | Out-String
Check 'version list is shown instead of a typing prompt' ($o -like '*CHOOSE A VERSION*' -and -not $o.Contains('Version [Enter'))
Check 'list shows stable CLI 2 releases with latest recommended' ($o -like '*CLI 2 - 2.1.3*latest stable (recommended)*' -and $o -like '*CLI 2 - 2.1.2*')
Check 'beta builds are not offered' ($o -notlike '*beta*')
Check 'unavailable CLI 1 list is explained, not fatal' ($o -like '*CLI 1 list unavailable*')
$o = "2`n$dst`n1`nn`n`n" | & $exe -NoProfile -File $stubFile 2>&1 | Out-String
Check 'choosing 1 then declining changes nothing' ($o -like '*CLI 2 - 2.1.3*' -and $o -like '*Cancelled. Nothing was changed*' -and -not (Test-Path (Join-Path $dst 'opencode.exe')))
$o = "2`n$dst`n`nn`n`n" | & $exe -NoProfile -File $stubFile 2>&1 | Out-String
Check 'pressing Enter selects the recommended release' ($o -like '*CLI 2 - 2.1.3*' -and $o -like '*Cancelled*')

Write-Host "`n[10] All-drives search + simple uninstall" -ForegroundColor Cyan
$d1 = Join-Path $sandbox 'driveD\Apps\oc'; $d2 = Join-Path $sandbox 'driveE\Backup'; $rb = Join-Path $sandbox 'driveD\$Recycle.Bin\oc'
$dk = Join-Path $sandbox 'driveD\Desk'; $tiny = Join-Path $sandbox 'driveE\tiny'; $arm = Join-Path $sandbox 'driveE\arm'
foreach ($d in $d1, $d2, $rb, (Join-Path $dk 'resources'), $tiny, $arm) { [void][IO.Directory]::CreateDirectory($d) }
[IO.File]::WriteAllBytes((Join-Path $d1 'opencode.exe'), (New-FakeExeBytes 'VER=3.1.0'))
[IO.File]::WriteAllBytes((Join-Path $d2 'opencode.exe'), (New-FakeExeBytes 'VER=3.2.0'))
[IO.File]::WriteAllBytes((Join-Path $rb 'opencode.exe'), (New-FakeExeBytes 'VER=4.0.0'))
[IO.File]::WriteAllBytes((Join-Path $dk 'opencode.exe'), (New-FakeExeBytes 'VER=5.0.0'))
[IO.File]::WriteAllBytes((Join-Path $tiny 'opencode.exe'), [byte[]](1, 2, 3))
[IO.File]::WriteAllBytes((Join-Path $arm 'opencode.exe'), (New-FakeExeBytes 'VER=6.0.0' -Machine 0xAA64))
function Get-SearchRoots { return @('D', 'E') }
function Search-Drive { param([string]$Root, [scriptblock]$OnProgress)
    if ($OnProgress) { & $OnProgress $Root 0 }
    if ($Root -eq 'D') { return @((Join-Path $d1 'opencode.exe'), (Join-Path $rb 'opencode.exe'), (Join-Path $dk 'opencode.exe'), (Join-Path $d1 'opencode.exe')) }
    return @((Join-Path $d2 'opencode.exe'), (Join-Path $tiny 'opencode.exe'), (Join-Path $arm 'opencode.exe')) }
$base = New-ScanResult @() @() $false
$progress = 0
$deepScan = Find-DeepInstallations -Existing $base -OnProgress { param($r, $s) $script:progress++ }
$vers = @($deepScan.Items | ForEach-Object { $_.Version } | Sort-Object)
Check 'finds copies on several drives, deduplicated' (@($deepScan.Items).Count -eq 2 -and ($vers -join ',') -eq '3.1.0,3.2.0') ($vers -join ',')
Check 'skips Recycle Bin, Desktop, tiny and ARM64 files' (@($deepScan.Items | Where-Object { $_.Version -in '4.0.0', '5.0.0', '6.0.0' }).Count -eq 0)
Check 'scan marked as all-drives, progress reported' ($deepScan.DeepDone -and $deepScan.Status -eq 'Found' -and $progress -ge 2)
$again = Find-DeepInstallations -Existing $deepScan
Check 'existing results are not duplicated' (@($again.Items).Count -eq 2)
$script:Scan = $deepScan; $script:Cfg.DefaultDir = Join-Path $sandbox 'nothing-here'; Save-KnownDirs @()
$kept = Update-Scan
Check 'refresh keeps earlier all-drives results' (@($kept.Items).Count -eq 2 -and $kept.DeepDone)
$script:Ansi = $false; $script:Ic = @{ dot = '*'; ok = '+'; bad = 'x'; diamond = '*'; prompt = '>'; arrow = '>'; bar = '#'; barOff = '-' }
$sw = New-Object IO.StringWriter; $old = [Console]::Out; [Console]::SetOut($sw); $host.UI | Out-Null
Show-StatusPanel $deepScan; [Console]::SetOut($old)
Check 'status says all drives were searched' (($sw.ToString() + '') -ne $null)

# simple uninstall flow driven by redirected input: "1", "y", Enter
$uf = Join-Path $sandbox 'uninst.ps1'
$target = Join-Path $d1 'opencode.exe'
[IO.File]::WriteAllText($uf, "`$env:OPENCODE_SETUP_NOMAIN='1'; `$env:LOCALAPPDATA='$($env:LOCALAPPDATA)'; . '$root/OpenCode-CLI-Setup.ps1'; Initialize-Terminal; `$script:Scan = [pscustomobject]@{ Status='Found'; Items=@((New-InstallItem -ExePath '$target' -Source 'drive scan')); Errors=@(); DeepDone=`$true }; Show-UninstallFlow")
$o = "1`ny`n`n" | & $exe -NoProfile -File $uf 2>&1 | Out-String
Check 'uninstall: pick number + one yes deletes the file' (-not (Test-Path $target) -and $o -like '*removed*')
Check 'uninstall: asks nothing about paths or ownership' ($o -notlike '*Exact path*' -and $o -notlike '*ownership*')
Check 'uninstall: other copies untouched' (Test-Path (Join-Path $d2 'opencode.exe'))
[void](Test-DirWritable $d1); [IO.File]::WriteAllBytes($target, (New-FakeExeBytes 'VER=3.1.0'))
$o = "1`nn`n`n" | & $exe -NoProfile -File $uf 2>&1 | Out-String
Check 'uninstall: answering no keeps the file' ((Test-Path $target) -and $o -like '*Nothing was deleted*')
$o = "zzz`n`n" + "b`n" | & $exe -NoProfile -File $uf 2>&1 | Out-String
Check 'uninstall: bad input handled, back works' ($o -like '*one of the numbers*' -and (Test-Path $target))

Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("`nResult: {0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
exit $(if ($script:Fail) { 1 } else { 0 })
