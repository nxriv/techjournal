<#
.SYNOPSIS
  A PowerShell module that provides multiple vCenter utils
  
.DESCRIPTION
   - Main menu (Invoke-480Landing)
   - Cloning wizard (Invoke-480Cloner)
   - Power operations (Invoke-480PowerOps)
   - Shared folder/VM selector (Select-VMFromFolders)
   - JSON-based config for some defaults 
   - Basic menu logic (like going back)
   
.NOTES
  Version:        1.0
  Author:         Nick Rivera
  Date:           2025-02-20
#>

function Show-480Banner {
    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "   480-UTILS: VMware Cloning & Utilities - Main Menu   " -ForegroundColor Green
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
}

function PromptWithDefault {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$DefaultValue
    )

    if ($DefaultValue -and $DefaultValue -ne "") {
        $prompt = "$Message [$DefaultValue]"
    }
    else {
        $prompt = $Message
    }

    $answer = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($answer) -and $DefaultValue) {
        return $DefaultValue
    }
    else {
        return $answer
    }
}

function Get-480Config {
    param(
        [string]$ConfigPath = ".\480-utils.json"
    )
    # https://stackoverflow.com/questions/62526696/how-do-i-create-a-json-in-powershell
    if (!(Test-Path $ConfigPath)) {
        $template = @{
            vCenterServer = "vcenter.nick.local"
            datastoreName = "datastore1"
            vmHost        = "192.168.3.226"
            networkName   = "480-WAN"
        }
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json?view=powershell-7.5
        $jsonOut = $template | ConvertTo-Json -Depth 3
        $jsonOut | Out-File $ConfigPath
        Write-Host "`nA default config file was created at '$ConfigPath'." -ForegroundColor Yellow
        Write-Host "Please review/edit it, then run again." -ForegroundColor Yellow
        return $null
    }
    else {
        return (Get-Content $ConfigPath -Raw | ConvertFrom-Json)
    }
}
# https://groupe-sii.github.io/cheat-sheets/powercli/index.html
function Connect-480vCenter {
    param(
        [string]$vCenterServer
    )

    $existingConn = Get-VIServer -Server $vCenterServer -ErrorAction SilentlyContinue
    if ($existingConn) {
        Write-Host "Already connected to $vCenterServer." -ForegroundColor Green
        return
    }

    $cred = Get-Credential -Message "Enter vCenter credentials for $vCenterServer"
    Write-Host "Connecting to vCenter: $vCenterServer..." -ForegroundColor Cyan
    Connect-VIServer -Server $vCenterServer -Credential $cred | Out-Null
    Write-Host "Connected to $vCenterServer." -ForegroundColor Green
}

function Select-VMFromFolders {
    while ($true) {
        Write-Host "`nRetrieving all VM folders..." -ForegroundColor Cyan
        $allFolders = Get-Folder -Type VM | Sort-Object Name
        if (!$allFolders) {
            Write-Host "No VM folders found." -ForegroundColor Red
            return $null
        }

        Write-Host "`nSelect a VM folder (or type B to go back):"
        for ($i=0; $i -lt $allFolders.Count; $i++) {
            Write-Host "[$i] $($allFolders[$i].Name)"
        }
        $folderChoice = Read-Host "Folder index or (b)ack?"
        
        if ($folderChoice -eq 'B') {
            return $null
        }
        # ^\d+$ = digits 0-9 only, one or more
        if ($folderChoice -notmatch '^\d+$' -or $folderChoice -ge $allFolders.Count) {
            Write-Host "Invalid folder index. Try again." -ForegroundColor Red
            continue
        }
        
        $selectedFolder = $allFolders[$folderChoice]
        Write-Host "`nYou selected folder: $($selectedFolder.Name)" -ForegroundColor Green

        while ($true) {
            $vmList = Get-VM -Location $selectedFolder | Sort-Object Name
            if (!$vmList) {
                Write-Host "No VMs found in '$($selectedFolder.Name)'. Going back to folder selection." -ForegroundColor Yellow
                break
            }

            Write-Host "`nFound these VMs in '$($selectedFolder.Name)':" -ForegroundColor Cyan
            for ($j=0; $j -lt $vmList.Count; $j++) {
                Write-Host "[$j] $($vmList[$j].Name)"
            }
            $vmChoice = Read-Host "Select VM Index or b to go back."

            if ($vmChoice -eq 'B') {
                break
            }
            if ($vmChoice -notmatch '^\d+$' -or $vmChoice -ge $vmList.Count) {
                Write-Host "Invalid VM index. Try again." -ForegroundColor Red
                continue
            }

            $chosenVM = $vmList[$vmChoice]
            Write-Host "`nYou picked VM: $($chosenVM.Name)" -ForegroundColor Green
            return $chosenVM
        }
    }
}

function Invoke-480Cloner {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = ".\480-utils.json"
    )

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "                      480 CLONER WIZARD                        " -ForegroundColor Green
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    $config = Get-480Config -ConfigPath $ConfigPath
    if (!$config) {
        return
    }

    $vCenterServer = PromptWithDefault "Enter vCenter Server" $config.vCenterServer
    Connect-480vCenter -vCenterServer $vCenterServer

    $datastoreName = PromptWithDefault "Datastore name" $config.datastoreName
    $vmHostName    = PromptWithDefault "VMHost name"    $config.vmHost
    $networkName   = PromptWithDefault "Network name"   $config.networkName

    $baseVM = Select-VMFromFolders
    if (!$baseVM) {
        Write-Host "No valid VM selected; returning to main menu." -ForegroundColor Yellow
        return
    }
    # this was useful for all snapshot related commands hereon https://www.it-react.com/index.php/2024/02/11/mastering-vmware-snapshots-with-powershell-powercli/
    $makeSnapshot = Read-Host "Create a new snapshot on the base VM first? (Y/N)"
    if ($makeSnapshot -eq 'Y') {
        $snapName = Read-Host "Snapshot name?"
        New-Snapshot -VM $baseVM -Name $snapName
        Write-Host "Snapshot '$snapName' created on $($baseVM.Name)." -ForegroundColor Green
    }

    $cloneName = Read-Host "Clone VM name?"
    $cloneType = Read-Host "Full or Linked clone? (F/L)"
    $useFull   = ($cloneType -eq 'F')

    if ($useFull) {
        Write-Host "You chose FULL clone." -ForegroundColor Magenta
    }
    else {
        Write-Host "You chose LINKED clone." -ForegroundColor Magenta
    }

    $snapRefName = Read-Host "Name of the reference snapshot?" # may error?

    if ($useFull) {
        $tempName = "$cloneName.tempLinked"
        Write-Host "`nCreating temporary linked clone '$tempName' from '$($baseVM.Name)'..." -ForegroundColor DarkYellow
        $tempLinked = New-VM -LinkedClone `
                             -Name $tempName `
                             -VM $baseVM `
                             -ReferenceSnapshot $snapRefName `
                             -VMHost $vmHostName `
                             -Datastore $datastoreName

        Write-Host "`nCreating full clone '$cloneName' from '$tempName'..." -ForegroundColor DarkYellow
        $finalClone = New-VM -Name $cloneName `
                             -VM $tempLinked `
                             -VMHost $vmHostName `
                             -Datastore $datastoreName

        Write-Host "Removing temporary linked clone '$tempName'..." -ForegroundColor Yellow
        Remove-VM -VM $tempName -Confirm:$false
    }
    else {
        Write-Host "`nCreating linked clone '$cloneName' from '$($baseVM.Name)', snapshot '$snapRefName'..." -ForegroundColor DarkYellow
        $finalClone = New-VM -LinkedClone `
                             -Name $cloneName `
                             -VM $baseVM `
                             -ReferenceSnapshot $snapRefName `
                             -VMHost $vmHostName `
                             -Datastore $datastoreName
    }

    Write-Host "`nSetting network adapter to '$networkName'..." -ForegroundColor Cyan
    Get-VM -Name $cloneName | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $networkName -Confirm:$false

    $postSnap = Read-Host "Create a snapshot on the new clone? (Y/N)"
    if ($postSnap -eq 'Y') {
        $postSnapName = Read-Host "Snapshot name?"
        New-Snapshot -VM $cloneName -Name $postSnapName
        Write-Host "Snapshot '$postSnapName' created on '$cloneName'." -ForegroundColor Green
    }

    Write-Host "`nAll done! Clone '$cloneName' created on network '$networkName'." -ForegroundColor Green
}

function Invoke-480PowerOps {
    param(
        [string]$ConfigPath = ".\480-utils.json"
    )

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "                     480 POWER OPERATIONS                      " -ForegroundColor Green
    Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    $config = Get-480Config -ConfigPath $ConfigPath
    if (!$config) {
        return
    }

    $vCenterServer = PromptWithDefault "Enter vCenter Server" $config.vCenterServer
    Connect-480vCenter -vCenterServer $vCenterServer

    while ($true) {
        $targetVM = Select-VMFromFolders
        if (!$targetVM) {
            Write-Host "Returning to main menu..." -ForegroundColor Yellow
            return
        }

        $currentState = $targetVM.PowerState
        Write-Host "Current power state: $currentState" -ForegroundColor Cyan
        # a switch statement here is much better than elseif but it works and i dont want to change it, i probably will later
        # even better, would be if i used enums
        # not familiar enough with them in powershell like i am with java - seems ps ones are more about typed numeric values (similar to c#?) than object models 
        $validActions = @()
        if ($currentState -eq "PoweredOff") {
            $validActions += "PowerOn"
        }
        elseif ($currentState -eq "PoweredOn") {
            $validActions += "PowerOff"
            $validActions += "Suspend"
            $validActions += "Restart"
        }
        elseif ($currentState -eq "Suspended") {
            $validActions += "PowerOn"
        }

        if ($validActions.Count -eq 0) {
            Write-Host "No valid actions for state '$currentState'." -ForegroundColor Yellow
        }
        else {
            Write-Host "`nValid actions for VM '$($targetVM.Name)':" -ForegroundColor Yellow
            for ($i=0; $i -lt $validActions.Count; $i++) {
                Write-Host "[$i] $($validActions[$i])"
            }
            $actionPick = Read-Host "Which action index? (b to go back)"

            if ($actionPick -eq 'B') {
                continue
            }

            if ($actionPick -notmatch '^\d+$' -or $actionPick -ge $validActions.Count) {
                Write-Host "Invalid action." -ForegroundColor Red
            }
            else {
                $chosenAction = $validActions[$actionPick]
                # will do switch action here at least
                switch ($chosenAction) {
                    "PowerOn" {
                        Write-Host "Powering on VM..." -ForegroundColor Magenta
                        Start-VM $targetVM | Out-Null
                        Write-Host "VM is now powered on." -ForegroundColor Green
                    }
                    "PowerOff" {
                        Write-Host "Powering off VM..." -ForegroundColor Magenta
                        Stop-VM $targetVM -Confirm:$false | Out-Null
                        Write-Host "VM is now powered off." -ForegroundColor Green
                    }
                    "Suspend" {
                        Write-Host "Suspending VM..." -ForegroundColor Magenta
                        Suspend-VM $targetVM -Confirm:$false | Out-Null
                        Write-Host "VM is now suspended." -ForegroundColor Green
                    }
                    "Restart" {
                        Write-Host "Restarting VM (guest OS)..." -ForegroundColor Magenta
                        Restart-VMGuest -VM $targetVM -Confirm:$false | Out-Null
                        Write-Host "VM guest OS restart initiated." -ForegroundColor Green
                    }
                }
            }
        }

        Write-Host "`nPress Enter to pick another VM or type B to return to main menu." -NoNewline
        $resp = Read-Host ""
        if ($resp -eq "B") {
            Write-Host "Returning to main menu..." -ForegroundColor Green
            return
        }
    }
}

function Invoke-480Landing {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = ".\480-utils.json"
    )

    while ($true) {
        Clear-Host
        Show-480Banner

        Write-Host "Please choose an option:" -ForegroundColor Yellow
        Write-Host "[1] Cloning Wizard"
        Write-Host "[2] Power Operations"
        Write-Host "[3] Exit"

        $choice = Read-Host "Enter choice (1/2/3)"
        switch ($choice) {
            "1" {
                Invoke-480Cloner -ConfigPath $ConfigPath
            }
            "2" {
                Invoke-480PowerOps -ConfigPath $ConfigPath
            }
            "3" {
                Write-Host "Exiting 480-UTILS. Goodbye!" -ForegroundColor Green
                return
            }
            default {
                Write-Host "Invalid selection. Try again." -ForegroundColor Red
            }
        }

        Write-Host "`nPress Enter to continue..." -NoNewline
        [void][System.Console]::ReadKey() # TIL casting void functions similarly to Out-Null, .NET feature. i still prefer java
    }
}

Export-ModuleMember -Function `
  Show-480Banner, PromptWithDefault, Get-480Config, Connect-480vCenter, `
  Select-VMFromFolders, Invoke-480Cloner, Invoke-480PowerOps, Invoke-480Landing
