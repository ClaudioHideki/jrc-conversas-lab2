# Pure Windows PowerShell contracts. The injected runner never invokes Docker.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'broker_https_cleanup.ps1')
$script:Passed = 0
$script:Failed = 0

function Assert-Contract([bool]$Condition,[string]$Code) {
  if (-not $Condition) { throw $Code }
}
function Test-Contract([string]$Name,[scriptblock]$Body) {
  try { & $Body; $script:Passed++; Write-Output "PASS $Name" }
  catch { $script:Failed++; Write-Output "FAIL $Name : $($_.Exception.Message)" }
}
function New-CleanupFixture {
  $state = @{ Running=$true; Attached=$true; StopExit=0; DisconnectExit=0; InventoryExit=0;
    KeepRunning=$false; KeepAttached=$false; LabelValid=$true; RunnerThrows=$false; NullRailsInventory=$false;
    MarkerExit=0; NetworkLabelValid=$true;
    Calls=[Collections.Generic.List[string]]::new() }
  $label = 'broker-https-11111111-1111-4111-8111-111111111111'
  $network = 'jrc-broker-https-11111111'
  $container = "$network-api"
  $runner = {
    param([string[]]$DockerArguments)
    $state.Calls.Add(($DockerArguments -join ' '))
    if ($state.RunnerThrows) { throw 'SIMULATED_DOCKER_UNAVAILABLE' }
    $code=0; $output=''
    switch ($DockerArguments[0]) {
      'exec' { $code=$state.MarkerExit }
      'ps' {
        $code=$state.InventoryExit
        if ($DockerArguments -contains '-a' -or $state.Running) { $output=$container }
      }
      'inspect' {
        if ($DockerArguments[-1] -eq 'rails-lab') {
          $networks=@{}; if($state.Attached){$networks[$network]=@{}}
          $output=$networks|ConvertTo-Json -Compress
          if($state.NullRailsInventory){$output='null'}
        } else {
          $actualLabel=if($state.LabelValid){$label}else{'another-task'}
          $output="$actualLabel|$($state.Running.ToString().ToLowerInvariant())"
        }
      }
      'stop' { $code=$state.StopExit; if($code -eq 0 -and -not $state.KeepRunning){$state.Running=$false} }
      'network' {
        switch($DockerArguments[1]) {
          'ls' { $output=$network }
          'inspect' { $output=if($state.NetworkLabelValid){$label}else{'another-task'} }
          'disconnect' { $code=$state.DisconnectExit; if($code -eq 0 -and -not $state.KeepAttached){$state.Attached=$false} }
          default { throw 'UNEXPECTED_NETWORK_MUTATION' }
        }
      }
      default { throw 'UNEXPECTED_DOCKER_MUTATION' }
    }
    [pscustomobject]@{ ExitCode=$code; Output=$output }
  }.GetNewClosure()
  @{State=$state; Arguments=@{Runner=$runner; Containers=@($container); Label=$label; Network=$network;
      RailsContainer='rails-lab'; Directory='/tmp/broker_https_11111111-1111-4111-8111-111111111111';
      RunId='11111111-1111-4111-8111-111111111111'} }
}

Test-Contract 'success requires stopped containers and detached Rails' {
  $fixture=New-CleanupFixture; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract ($result.Verified -and -not $fixture.State.Running -and -not $fixture.State.Attached) 'SUCCESS_NOT_VERIFIED'
  $message=Complete-BrokerHttpsCleanup -Cleanup $result
  Assert-Contract ($message -match 'verified') 'MISSING_CONDITIONAL_SUCCESS_MESSAGE'
  Assert-Contract (@($fixture.State.Calls|Where-Object{$_ -match '^(rm|volume|system|container rm)\b'}).Count -eq 0) 'DESTRUCTIVE_COMMAND'
}
Test-Contract 'stop exit failure cannot claim cleanup success' {
  $fixture=New-CleanupFixture; $fixture.State.StopExit=1; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'STOP_FAILURE_ACCEPTED'
}
Test-Contract 'disconnect exit failure cannot claim cleanup success' {
  $fixture=New-CleanupFixture; $fixture.State.DisconnectExit=1; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'DISCONNECT_FAILURE_ACCEPTED'
}
Test-Contract 'unavailable inventory is unverified' {
  $fixture=New-CleanupFixture; $fixture.State.InventoryExit=1; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'UNREADABLE_INVENTORY_ACCEPTED'
}
Test-Contract 'mismatched label is preserved and fails closed' {
  $fixture=New-CleanupFixture; $fixture.State.LabelValid=$false; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'WRONG_LABEL_ACCEPTED'
  Assert-Contract (@($fixture.State.Calls|Where-Object{$_ -match '^stop '}).Count -eq 0) 'FOREIGN_CONTAINER_STOPPED'
}
Test-Contract 'successful stop command still requires observed stopped state' {
  $fixture=New-CleanupFixture; $fixture.State.KeepRunning=$true; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'RUNNING_CONTAINER_ACCEPTED'
}
Test-Contract 'successful disconnect still requires observed detached state' {
  $fixture=New-CleanupFixture; $fixture.State.KeepAttached=$true; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'ATTACHED_RAILS_ACCEPTED'
}
Test-Contract 'cleanup fault makes an otherwise successful run fail' {
  $caught=$null
  try { Complete-BrokerHttpsCleanup -Cleanup ([pscustomobject]@{Verified=$false;Errors=@('STOP_FAILED')})|Out-Null }
  catch { $caught=$_ }
  Assert-Contract ($null -ne $caught -and $caught.Exception.Message -match 'CLEANUP_UNVERIFIED') 'CLEANUP_DID_NOT_FAIL_RUN'
}
Test-Contract 'cleanup fault preserves primary stack failure' {
  $primary=[InvalidOperationException]::new('PRIMARY_STACK_FAULT'); $caught=$null
  try { Complete-BrokerHttpsCleanup -Cleanup ([pscustomobject]@{Verified=$false;Errors=@('STOP_FAILED')}) -PrimaryFailure $primary -WarningAction SilentlyContinue|Out-Null }
  catch { $caught=$_ }
  Assert-Contract ($null -ne $caught -and [object]::ReferenceEquals($caught.Exception,$primary)) 'PRIMARY_FAILURE_REPLACED'
}
Test-Contract 'verified cleanup does not turn a primary fault into success' {
  $primary=[InvalidOperationException]::new('PRIMARY_STACK_FAULT'); $caught=$null; $messages=@()
  try { $messages=@(Complete-BrokerHttpsCleanup -Cleanup ([pscustomobject]@{Verified=$true;Errors=@()}) -PrimaryFailure $primary) }
  catch { $caught=$_ }
  Assert-Contract ($null -ne $caught -and [object]::ReferenceEquals($caught.Exception,$primary) -and $messages.Count -eq 0) 'PRIMARY_FAULT_REPORTED_AS_SUCCESS'
}
Test-Contract 'runner exceptions cannot claim cleanup success' {
  $fixture=New-CleanupFixture; $fixture.State.RunnerThrows=$true; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'RUNNER_EXCEPTION_ACCEPTED'
}
Test-Contract 'null Rails inventory is not evidence of detachment' {
  $fixture=New-CleanupFixture; $fixture.State.NullRailsInventory=$true; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'NULL_RAILS_INVENTORY_ACCEPTED'
}
Test-Contract 'failed worker stop request is unverified' {
  $fixture=New-CleanupFixture; $fixture.State.MarkerExit=1; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'WORKER_STOP_REQUEST_FAILURE_ACCEPTED'
}
Test-Contract 'foreign network is never disconnected' {
  $fixture=New-CleanupFixture; $fixture.State.NetworkLabelValid=$false; $arguments=$fixture.Arguments
  $result=Invoke-BrokerHttpsCleanup @arguments
  Assert-Contract (-not $result.Verified) 'FOREIGN_NETWORK_ACCEPTED'
  Assert-Contract (@($fixture.State.Calls|Where-Object{$_ -match '^network disconnect '}).Count -eq 0) 'FOREIGN_NETWORK_DISCONNECTED'
}
Test-Contract 'invalid target is rejected before any command' {
  $fixture=New-CleanupFixture; $arguments=$fixture.Arguments; $arguments.Directory='/tmp/another-task'; $caught=$null
  try { Invoke-BrokerHttpsCleanup @arguments|Out-Null } catch {$caught=$_}
  Assert-Contract ($null -ne $caught -and $fixture.State.Calls.Count -eq 0) 'INVALID_TARGET_WAS_USED'
}
Write-Output "Cleanup contracts: $script:Passed passed, $script:Failed failed; Docker was not invoked."
if($script:Failed){exit 1}
