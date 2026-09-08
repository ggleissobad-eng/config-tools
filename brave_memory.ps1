
Skip to content
ggleissobad-eng
config-tools
Repository navigation
Code
Issues
Pull requests
Agents
Actions
Projects
Wiki
Security and quality
Insights
Settings
Files
Go to file
t
T
brave_memory.ps1
config-tools
/
brave_memory.ps1
in
main

Edit

Preview
Indent mode

Spaces
Indent size

4
Line wrap mode

No wrap
Editing brave_memory.ps1 file contents
  1
  2
  3
  4
  5
  6
  7
  8
  9
 10
 11
 12
 13
 14
 15
 16
 17
 18
 19
 20
 21
 22
 23
 24
 25
 26
 27
 28
 29
 30
 31
 32
 33
 34
 35
 36
 37
 38
 39
 40
 41
 42
 43
 44
 45
 46
 47
 48
 49
 50
 51
 52
 53
 54
 55
 56
 57
 58
 59
 60
 61
 62
 63
 64
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
                
                # Debug: show first 500 chars
                Write-Host "`n[DEBUG] First 500 chars of response:"
                Write-Host $response.Substring(0, [Math]::Min(500, $response.Length))
                Write-Host ""
                
                $offsets = @{}
                
                # Try multiple patterns
                $patterns = @(
                    '#define\s+([A-Z_0-9]+)\s+(0x[0-9a-fA-F]+)',
                    'const\s+u?int(?:32|64)?\s+([A-Z_0-9]+)\s*=\s*(0x[0-9a-fA-F]+)',
                    '([A-Z_0-9]+)\s*=\s*(0x[0-9a-fA-F]+)'
                )
                
                foreach ($pattern in $patterns) {
                    $regex = [regex]$pattern
                    $matches = $regex.Matches($response)
                    if ($matches.Count -gt 0) {
                        Write-Host "[DEBUG] Pattern matched: $($matches.Count) offsets found" -ForegroundColor Green
                        foreach ($match in $matches) {
                            $name = $match.Groups[1].Value
                            $hex = $match.Groups[2].Value
                            $offsets[$name] = [int64]$hex
                        }
                        break
                    }
                }
                
                if ($offsets.Count -eq 0) {
                    Write-Host "[DEBUG] No patterns matched. Response might be different format." -ForegroundColor Yellow
                    Write-Host "[DEBUG] Full response (first 2000 chars):" -ForegroundColor Yellow
                    Write-Host $response.Substring(0, [Math]::Min(2000, $response.Length)) -ForegroundColor Yellow
                }
                
                Log "Loaded $($offsets.Count) offsets" "SUCCESS"
                return $offsets
            }
        } catch {
            Log "Failed to fetch from $url : $_" "WARN"
        }
Use Control + Shift + m to toggle the tab key moving focus. Alternatively, use esc then tab to move to the next interactive element on the page.
 
