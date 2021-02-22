#requires -Version 5.0

using namespace KeeperSecurity

class AuthPersistentFlowCallback : Authentication.Sync.IAuthSyncCallback, Authentication.IAuthInfoUI {
    [void]RegionChanged([string]$newRegion) {
        Write-Information -MessageData "Region changed: $newRegion"
    }

    [void]SelectedDevice([string]$deviceToken) {
        # Write-Host "SelectedDevice: Not Supported in Daemon Mode" -ForegroundColor Red
    }

    [void]OnNextStep() {
        # Write-Host "OnNextSteps: Not Supported in Daemon Mode" -ForegroundColor Red
    }

    [void]ExecuteStepAction($step, $action) {
        # Write-Host "ExecuteStepAction: Not Supported in Daemon Mode. step={$step}, action={$action}" -ForegroundColor Red
    }
}

function Connect-KeeperDaemon {
<#
    .Synopsis
    Login to Keeper using persistent login

   .Parameter Username
    Account email

    .Parameter NewLogin
    Do not use Last Login information

    .Parameter Server
    Change default keeper server
#>
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)][string] $Username,
        [Parameter()][switch] $NewLogin,
        [Parameter()][string] $Server
    )

    Write-Host "Connecting Keeper (Daemon)"

    $_ = Disconnect-Keeper -Resume

    $path = "/Users/idimov/.keeper/config.json"
    $storage = New-Object Configuration.JsonConfigurationStorage($path)

    if (-not $Server) {
        $Server = $storage.LastServer
        if ($Server) {
            Write-Information -MessageData "`nUsing Last Known Keeper Server: $Server`n"
        } else {
            Write-Information -MessageData "`nUsing Default Keeper Server: $([Authentication.KeeperEndpoint]::DefaultKeeperServer)`n"
        }
    } else {
        Write-Information -MessageData "`nUsing Provided Keeper Server: $Server`n"
    }

    $endpoint = New-Object Authentication.KeeperEndpoint($Server, $storage.Servers)
    $authFlow = New-Object Authentication.Sync.AuthSync($storage, $endpoint)

    $authFlow.UiCallback = New-Object AuthPersistentFlowCallback
    $authFlow.ResumeSession = $true

    if (-not $NewLogin.IsPresent) {
        if (-not $Username) {
            $Username = $storage.LastLogin
        }
    }

    if ($Username) {
        Write-Host "$('Keeper Username:'.PadLeft(21, ' ')) $Username"
    } else {
        Write-Warning "This authentication flow does not support manual entry. Only persistent login is supported at this time. Please provide config.json file with valid clone code."
        return
    }

    $_ = $authFlow.Login($Username).GetAwaiter().GetResult()

    if ($authFlow.Step.State -ne [Authentication.Sync.AuthState]::Connected) {
        if ($authFlow.Step -is [Authentication.Sync.ErrorStep]) {
            Write-Host $authFlow.Step.Message -ForegroundColor Red
        }
        Write-Warning "Not authenticated. Only persistent login is supported at this time. Please provide config.json file with valid clone code. EC=1"
        Write-Warning ("Step State: " + $authFlow.Step.State + ", Message: '" + $authFlow.Step.Message + "'; IsCompleted: " + $authFlow.IsCompleted + "`n")
        return
    }

    $auth = $authFlow
    if ([Authentication.AuthExtensions]::IsAuthenticated($auth)) {
        $Script:Auth = $auth
        Write-Debug -Message "Connected to Keeper as $Username"

        $Script:Vault = New-Object Vault.VaultOnline($auth)
        $task = $Script:Vault.SyncDown()
        Write-Information -MessageData 'Syncing ...'
        $_ = $task.GetAwaiter().GetResult()
        $Script:Vault.AutoSync = $true

        [Vault.VaultData]$vault = $Script:Vault
        Write-Information -MessageData "Decrypted $($vault.RecordCount) record(s)"
        $_ = Set-KeeperLocation -Path '\'
    } else {
        Write-Warning "Not authenticated. Only persistent login is supported at this time. Please provide config.json file with valid clone code. EC=2"
        return
    }

    Write-Host "✅ Connected and authenticated to Keeper (Daemon)" -ForegroundColor Green

    return $auth
}

New-Alias -Name kcp -Value Connect-KeeperDaemon
