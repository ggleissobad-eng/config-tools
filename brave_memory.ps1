# RAM-only FFlag injector - zero disk execution
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -Command "IEX (New-Object Net.WebClient).DownloadString('https://your-host.com/brave_memory.ps1')"

$ErrorActionPreference = "SilentlyContinue"

function Log {
    param([string]$msg, [string]$level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [$level] $msg"
}

function Fetch-Offsets {
    $urls = @(
        'https://offsets.imtheo.lol/fflags.hpp',
        'https://offsets.femboythighs.org/fflags.hpp'
    )
    
    foreach ($url in $urls) {
        try {
            Log "Fetching offsets from $url"
            $response = (New-Object Net.WebClient).DownloadString($url)
            if ($response) {
                Log "Parsing offsets..."
                $offsets = @{}
                
                # Use the working pattern from decompiled brave.py
                $regex = [regex]'(\w+)\s*=\s*(0x[0-9A-Fa-f]+)'
                $matches = $regex.Matches($response)
                
                foreach ($match in $matches) {
                    $name = $match.Groups[1].Value
                    $hex = $match.Groups[2].Value
                    
                    # Clean prefix (remove FFlag, DFFlag, etc.)
                    foreach ($prefix in @('FFlag', 'DFFlag', 'FInt', 'DFInt', 'FString', 'DFString', 'FLog')) {
                        if ($name.StartsWith($prefix)) {
                            $name = $name.Substring($prefix.Length)
                            break
                        }
                    }
                    
                    $offsets[$name] = [int64]$hex
                }
                
                if ($offsets.Count -gt 0) {
                    Log "Loaded $($offsets.Count) offsets" "SUCCESS"
                    return $offsets
                }
            }
        } catch {
            Log "Failed to fetch from $url : $_" "WARN"
        }
    }
    Log "Could not fetch offsets from any source" "ERROR"
    return $null
}

function Open-FilePicker {
    [Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $browser = New-Object System.Windows.Forms.OpenFileDialog
    $browser.Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $browser.InitialDirectory = "$env:APPDATA\Local\Brave"
    $browser.Title = "Select FFlags Config"
    
    if ($browser.ShowDialog() -eq "OK") {
        return $browser.FileName
    }
    return $null
}

function Load-Config {
    param([string]$filePath)
    try {
        Log "Loading config from $filePath"
        $json = Get-Content $filePath -Raw | ConvertFrom-Json
        
        if ($json.flags) {
            return $json.flags
        } else {
            return $json
        }
    } catch {
        Log "Failed to load config: $_" "ERROR"
        return $null
    }
}

function Get-RobloxProcess {
    $proc = Get-Process -Name "RobloxPlayerBeta" -ErrorAction SilentlyContinue
    if ($proc) {
        Log "Found Roblox process (PID: $($proc.Id))" "SUCCESS"
        return $proc
    }
    Log "Roblox process not found" "ERROR"
    return $null
}

function Write-Flag {
    param(
        [System.Diagnostics.Process]$process,
        [int64]$baseAddress,
        [string]$flagName,
        [int64]$offset,
        [object]$value
    )
    
    try {
        $address = $baseAddress + $offset
        
        # Convert value to bytes
        if ($value -is [bool]) {
            if ($value -eq $true) {
                $bytes = @([byte]1)
            } else {
                $bytes = @([byte]0)
            }
        } elseif ($value -is [int]) {
            $bytes = [BitConverter]::GetBytes([int32]$value)
        } else {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($value.ToString())
        }
        
        # Use NtWriteVirtualMemory via P/Invoke
        $ntdll = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer(
            [System.Runtime.InteropServices.Marshal]::GetProcAddress(
                [System.Runtime.InteropServices.Marshal]::LoadLibrary("ntdll"),
                "NtWriteVirtualMemory"
            ),
            [delegate] @(
                [IntPtr], [IntPtr], [IntPtr], [UIntPtr], [IntPtr]
            ) -As [type] "Int32"
        )
        
        $hProcess = $process.Handle
        $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
        [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $buffer, $bytes.Length)
        
        $written = 0
        $result = $ntdll.Invoke($hProcess, [IntPtr]$address, $buffer, [UIntPtr]$bytes.Length, [ref]$written)
        
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        
        if ($result -eq 0) {
            return $true
        } else {
            Log "Write failed for $flagName : 0x$($result.ToString('X'))" "ERROR"
            return $false
        }
    } catch {
        Log "Error writing flag $flagName : $_" "ERROR"
        return $false
    }
}

function Inject-Flags {
    param([System.Diagnostics.Process]$process, [hashtable]$flags, [int64]$baseAddress)
    
    $success = 0
    Log "Injecting $($flags.Count) flags..."
    
    foreach ($name in $flags.Keys) {
        $flagData = $flags[$name]
        
        # Handle array or object format
        if ($flagData -is [array] -and $flagData.Count -ge 2) {
            $offset = $flagData[0]
            $value = $flagData[1]
        } elseif ($flagData -is [PSObject] -and $flagData.offset) {
            $offset = $flagData.offset
            $value = $flagData.value
        } else {
            Log "Invalid flag format for $name" "ERROR"
            continue
        }
        
        # Convert string offset to int if needed
        if ($offset -is [string]) {
            $offset = [int64]::Parse($offset, [System.Globalization.NumberStyles]::HexNumber)
        }
        
        if (Write-Flag $process $baseAddress $name $offset $value) {
            Log "✓ $name" "SUCCESS"
            $success++
        } else {
            Log "✗ $name" "ERROR"
        }
    }
    
    Log "Injection complete: $success/$($flags.Count)" "SUCCESS"
    return $success
}

function Unapply-Flags {
    param([System.Diagnostics.Process]$process, [hashtable]$flags, [int64]$baseAddress)
    
    $success = 0
    Log "Unapplying $($flags.Count) flags..."
    
    foreach ($name in $flags.Keys) {
        $flagData = $flags[$name]
        
        # Handle array or object format
        if ($flagData -is [array] -and $flagData.Count -ge 1) {
            $offset = $flagData[0]
        } elseif ($flagData -is [PSObject] -and $flagData.offset) {
            $offset = $flagData.offset
        } else {
            continue
        }
        
        # Convert string offset to int if needed
        if ($offset -is [string]) {
            $offset = [int64]::Parse($offset, [System.Globalization.NumberStyles]::HexNumber)
        }
        
        if (Write-Flag $process $baseAddress $name $offset 0) {
            Log "✓ $name unapplied" "INFO"
            $success++
        }
    }
    
    Log "Unapply complete: $success/$($flags.Count)" "SUCCESS"
    return $success
}

# Main execution
Write-Host "============================================================"
Write-Host "BRAVE - FFlag Injector (RAM-Only)"
Write-Host "============================================================`n"

# Fetch offsets
$offsets = Fetch-Offsets
if (!$offsets) {
    Read-Host "Press Enter to exit"
    exit
}

# File picker
Log "Opening file picker..."
$configFile = Open-FilePicker
if (!$configFile) {
    Log "No file selected" "WARN"
    Read-Host "Press Enter to exit"
    exit
}

# Load config
$flags = Load-Config $configFile
if (!$flags -or $flags.Count -eq 0) {
    Log "No flags in config" "WARN"
    Read-Host "Press Enter to exit"
    exit
}

Log "Loaded $($flags.Count) flags"

# Get Roblox process
$roblox = Get-RobloxProcess
if (!$roblox) {
    Read-Host "Press Enter to exit"
    exit
}

$baseAddress = $roblox.MainModule.BaseAddress

# Inject flags
Inject-Flags $roblox $flags $baseAddress

Write-Host "`n============================================================"
Write-Host "Ready. Close this window to exit (G key not available in PowerShell)"
Write-Host "============================================================`n"

Read-Host "Press Enter to exit"
