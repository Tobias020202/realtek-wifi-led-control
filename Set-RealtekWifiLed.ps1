<#
  Set-RealtekWifiLed.ps1
  ------------------------------------------------------------------
  Controls the status LED of Realtek Wi-Fi adapters whose Windows
  driver supports the "LedCtrl" registry value - the rtwlanu/rtwlans
  driver family and similar (RTL8188, 8192, 8723, 8812, 8814, 8821,
  8822, ...).

  The driver reads "LedCtrl" from the adapter's network class key on
  every (re)start:

      0 = LED off      1 = blink (driver default)      2 = LED on

  The script detects every Realtek Wi-Fi adapter, verifies driver
  support (driver INF and driver binary are checked for "LedCtrl"),
  saves a .reg backup of the class key, writes the value and restarts
  the selected adapter.

  Adapter selection:
      (no selector)  single adapter: used automatically
                     several adapters: interactive menu (with -Pause)
      -Adapter <n>   index from the list (1-based)
      -Adapter <s>   name substring (must match exactly one adapter)
      -All           every detected adapter

  Background: the value names were found as UTF-16 strings inside
  rtwlanu.sys, confirmed by Realtek INFs (HKR,defaults,LedCtrl,0,"1")
  and by the open-source Linux drivers of the same chips (module
  option rtw_led_ctrl). No firmware flashing, no binary patching.

  Examples:
      .\Set-RealtekWifiLed.ps1 -Value 0 -All
      .\Set-RealtekWifiLed.ps1 -Value 1 -Adapter 2
      .\Set-RealtekWifiLed.ps1 -Value 0 -DryRun

  Or simply double-click led-off.cmd / led-blink.cmd.
#>
param(
    [ValidateSet(0, 1, 2)]
    [int]$Value = 0,

    [string]$Adapter,
    [switch]$All,

    [switch]$DryRun,
    [switch]$NoRestart,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'

$ClassPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
$ValueNames = @{ 0 = 'LED off'; 1 = 'blink (driver default)'; 2 = 'LED on' }
$NewValue   = [string]$Value

function Close-IfPaused {
    if ($Pause) { Read-Host 'Press Enter to close.' }
}

function Test-DriverSupportsLedCtrl {
    param([string]$ServiceName)
    if (-not $ServiceName) { return $false }
    $sys = Join-Path 'C:\Windows\System32\drivers' ($ServiceName + '.sys')
    if (-not (Test-Path $sys)) { return $false }
    try {
        $image = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($sys))
        return $image.Contains('LedCtrl')
    } catch {
        return $false
    }
}

function Show-AdapterList {
    param($Items)
    Write-Host ''
    Write-Host 'Detected Realtek Wi-Fi adapters:'
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ('  [{0}] {1}  (registry key {2})' -f ($i + 1), $Items[$i].Desc, $Items[$i].KeyName)
    }
    Write-Host ''
}

# --- argument checks ----------------------------------------------------
if ($PSBoundParameters.ContainsKey('Adapter') -and $All) {
    Write-Host 'Use either -Adapter or -All, not both.' -ForegroundColor Red
    Close-IfPaused
    exit 2
}
if ($Adapter) { $Adapter = $Adapter.Trim() }

# --- administrator rights (request via UAC if needed) -------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) {
    Write-Host 'Requesting administrator rights (UAC)...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Value', $NewValue)
    if ($Adapter)   { $argList += @('-Adapter', ('"{0}"' -f $Adapter)) }
    if ($All)       { $argList += '-All' }
    if ($NoRestart) { $argList += '-NoRestart' }
    $argList += '-Pause'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host 'Elevation was cancelled - nothing was changed.' -ForegroundColor Red
        Close-IfPaused
        exit 1
    }
    exit 0
}

# --- find Realtek Wi-Fi adapters in the network class key ---------------
# Candidates: any Realtek wireless adapter, or any adapter whose driver
# INF installs the LedCtrl value (covers OEM-branded devices).
$targets = @()
Get-ChildItem $ClassPath -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^\d{4}$' } |
    ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $desc  = [string]$props.DriverDesc

        $infText = ''
        if ($props.InfPath) {
            $infFull = Join-Path 'C:\Windows\INF' ([string]$props.InfPath)
            if (Test-Path $infFull) {
                $infText = Get-Content -LiteralPath $infFull -Raw -ErrorAction SilentlyContinue
            }
        }

        $infHasLed     = $infText -match 'LedCtrl'
        $isRealtekWifi = ($desc -like '*Realtek*') -and ($desc -match 'Wireless|WiFi|WLAN|802\.11')

        if ($isRealtekWifi -or $infHasLed) {
            $supports = $infHasLed
            if (-not $supports) {
                $svc = (Get-ItemProperty -Path (Join-Path $_.PSPath 'Ndi') -Name 'Service' -ErrorAction SilentlyContinue).Service
                if (-not $svc) { $svc = $props.Service }
                $supports = Test-DriverSupportsLedCtrl ([string]$svc)
            }
            if ([string]::IsNullOrWhiteSpace($desc)) { $desc = 'Unknown adapter' }
            $targets += [pscustomobject]@{
                KeyPath  = $_.PSPath
                KeyName  = $_.PSChildName
                Desc     = $desc
                Instance = [string]$props.NetCfgInstanceId
                Supports = $supports
            }
        }
    }
$targets = @($targets | Sort-Object -Property KeyName)

if ($targets.Count -eq 0) {
    Write-Host 'No Realtek Wi-Fi adapter found.' -ForegroundColor Red
    Write-Host 'Is the adapter plugged in / installed?'
    Close-IfPaused
    exit 1
}

# --- adapter selection --------------------------------------------------
$selected = @()
if ($Adapter) {
    $numeric = $Adapter -match '^\d+$'
    if ($numeric) {
        $index = 0
        if ([int]::TryParse($Adapter, [ref]$index) -and $index -ge 1 -and $index -le $targets.Count) {
            $selected = @($targets[$index - 1])
        }
    }
    if ($selected.Count -eq 0) {
        $selected = @($targets | Where-Object { $_.Desc.IndexOf($Adapter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($selected.Count -eq 0) {
            if ($numeric) {
                Write-Host ('Adapter "{0}" is out of range (1-{1}) and matches no adapter name.' -f $Adapter, $targets.Count) -ForegroundColor Red
            } else {
                Write-Host ('No adapter matches "{0}".' -f $Adapter) -ForegroundColor Red
            }
            Show-AdapterList $targets
            Close-IfPaused
            exit 1
        }
        if ($selected.Count -gt 1) {
            Write-Host ('"{0}" matches {1} adapters - use the index or a more specific name.' -f $Adapter, $selected.Count) -ForegroundColor Red
            Show-AdapterList $targets
            Close-IfPaused
            exit 1
        }
    }
} elseif ($All) {
    $selected = $targets
} elseif ($targets.Count -eq 1) {
    $selected = $targets
} else {
    if (-not $Pause) {
        Write-Host ('{0} adapters detected - use -Adapter <index|name> or -All.' -f $targets.Count) -ForegroundColor Red
        Show-AdapterList $targets
        exit 1
    }
    Show-AdapterList $targets
    $attempt = 0
    while ($attempt -lt 3 -and $selected.Count -eq 0) {
        $answer = Read-Host ('Select adapter [1-{0}], A = all' -f $targets.Count)
        if ($null -eq $answer) { $answer = '' }
        $answer = [string]$answer
        if ($answer -match '^\s*([Aa]|[Aa][Ll][Ll])\s*$') {
            $selected = $targets
        } else {
            $chosen = 0
            if ([int]::TryParse($answer.Trim(), [ref]$chosen) -and $chosen -ge 1 -and $chosen -le $targets.Count) {
                $selected = @($targets[$chosen - 1])
            } else {
                Write-Host 'Invalid input.' -ForegroundColor Yellow
                $attempt++
            }
        }
    }
    if ($selected.Count -eq 0) {
        Write-Host 'No valid selection - nothing was changed.' -ForegroundColor Red
        Close-IfPaused
        exit 1
    }
}

$backupDir = Join-Path $PSScriptRoot 'backup'
if (-not $DryRun -and -not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

# --- apply --------------------------------------------------------------
foreach ($t in $selected) {
    Write-Host ''
    Write-Host ('Adapter:        {0}' -f $t.Desc)
    Write-Host ('Registry key:   {0}' -f $t.KeyName)
    if (-not $t.Supports) {
        Write-Host 'Warning: the driver does not seem to support LedCtrl - the setting may have no effect.' -ForegroundColor Yellow
    }

    $props = Get-ItemProperty -Path $t.KeyPath
    $currentText = '<not set>'
    if ($null -ne $props.LedCtrl) { $currentText = [string]$props.LedCtrl }
    $currentName = ''
    if ($currentText -match '^[012]$') { $currentName = ' ({0})' -f $ValueNames[[int]$currentText] }
    Write-Host ('Current LedCtrl: {0}{1}' -f $currentText, $currentName)

    if ($DryRun) {
        Write-Host ('[DryRun] Would set LedCtrl to "{0}" ({1}) and restart the adapter.' -f $NewValue, $ValueNames[$Value]) -ForegroundColor Cyan
        continue
    }

    $defaultsKey = Join-Path $t.KeyPath 'defaults'
    $needWrite = ($currentText -ne $NewValue)
    if (-not $needWrite -and (Test-Path $defaultsKey)) {
        $currentDefaults = (Get-ItemProperty -Path $defaultsKey -Name 'LedCtrl' -ErrorAction SilentlyContinue).LedCtrl
        if ($null -eq $currentDefaults -or ([string]$currentDefaults) -ne $NewValue) { $needWrite = $true }
    }

    if ($needWrite) {
        $stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
        $regFile = Join-Path $backupDir ('led-backup_{0}_{1}.reg' -f $t.KeyName, $stamp)
        $regPath = $t.KeyPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
        & reg.exe export $regPath $regFile /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $regFile)) {
            Write-Host 'Backup failed - the registry was NOT changed.' -ForegroundColor Red
            Close-IfPaused
            exit 1
        }
        Write-Host ('Backup saved:   {0}' -f $regFile)

        New-ItemProperty -Path $t.KeyPath -Name 'LedCtrl' -PropertyType String -Value $NewValue -Force | Out-Null
        if (Test-Path $defaultsKey) {
            New-ItemProperty -Path $defaultsKey -Name 'LedCtrl' -PropertyType String -Value $NewValue -Force | Out-Null
        }
        Write-Host ('LedCtrl set to "{0}" ({1}).' -f $NewValue, $ValueNames[$Value]) -ForegroundColor Green
    } else {
        Write-Host ('Already set to "{0}" - registry unchanged.' -f $NewValue)
    }
}

if ($DryRun) {
    Close-IfPaused
    exit 0
}

# --- restart only the selected adapters ---------------------------------
if (-not $NoRestart) {
    $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
    foreach ($t in $selected) {
        $instance = $t.Instance -replace '[{}]', ''
        $a = $null
        if ($instance) {
            $a = $allAdapters | Where-Object { ($_.InterfaceGuid.ToString() -replace '[{}]', '') -ieq $instance } | Select-Object -First 1
        }
        if (-not $a) {
            $a = $allAdapters | Where-Object { $_.InterfaceDescription -ieq $t.Desc } | Select-Object -First 1
        }
        if (-not $a) {
            Write-Host ''
            Write-Host ('Adapter "{0}" is not currently connected - restart skipped.' -f $t.Desc) -ForegroundColor Yellow
            continue
        }
        Write-Host ''
        Write-Host ('Restarting adapter "{0}" ...' -f $a.Name)
        try {
            Disable-NetAdapter -Name $a.Name -Confirm:$false
            Start-Sleep -Seconds 3
            Enable-NetAdapter -Name $a.Name -Confirm:$false
            Start-Sleep -Seconds 4
            Write-Host 'Adapter restarted.' -ForegroundColor Green
        } catch {
            Write-Host ('Note: could not restart the adapter automatically: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'If the LED is still on:'
Write-Host '  1. Unplug and replug the adapter.'
Write-Host '  2. If needed, reboot Windows (reloads the driver).'
Write-Host ''
Write-Host 'To revert: run led-blink.cmd (LedCtrl = 1).'
Close-IfPaused
