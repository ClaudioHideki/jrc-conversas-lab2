# Fail-closed laboratory cleanup. The runner returns ExitCode/Output and can be injected without Docker.
function Invoke-BrokerHttpsCleanupCommand {
  param([scriptblock]$Runner,[string[]]$DockerArguments)
  try {
    $result=& $Runner $DockerArguments
    if($null -eq $result -or $null -eq $result.ExitCode){throw 'INVALID_RUNNER_RESULT'}
    return $result
  } catch { return [pscustomobject]@{ExitCode=255;Output=''} }
}
function Invoke-BrokerHttpsCleanup {
  param([scriptblock]$Runner,[string[]]$Containers,[string]$Label,[string]$Network,[string]$RailsContainer,[string]$Directory,[string]$RunId)
  if($RunId -notmatch '^[a-f0-9]{8}-[a-f0-9-]{27}$' -or $Label -ne "broker-https-$RunId" -or
     $Network -ne "jrc-broker-https-$($RunId.Substring(0,8))" -or $Directory -ne "/tmp/broker_https_$RunId" -or
     @($Containers|Where-Object{$_ -notmatch ('^'+[regex]::Escape($Network)+'-(api|proxy|seed|broker-pg|rails-pg|redis)$')}).Count){
    throw 'UNEXPECTED_CLEANUP_TARGET'
  }
  $errors=[Collections.Generic.List[string]]::new()
  $observed=[Collections.Generic.List[object]]::new()
  $filter="label=jrc.task=$Label"
  $inventory=Invoke-BrokerHttpsCleanupCommand $Runner @('ps','-a','--filter',$filter,'--format','{{.Names}}')
  $known=@()
  if($inventory.ExitCode -ne 0){$errors.Add('CONTAINER_INVENTORY_UNVERIFIED');$known=$Containers}
  else {
    $known=@(([string]$inventory.Output -split '\r?\n')|Where-Object{$_ -ne ''})
    if(@($known|Where-Object{$_ -notin $Containers}).Count){$errors.Add('UNEXPECTED_LABELED_CONTAINER')}
  }
  $marker=Invoke-BrokerHttpsCleanupCommand $Runner @('exec',$RailsContainer,'ruby','-rjson','-e',
    'File.write(File.join(ARGV.fetch(0),"stop_requested.json"),JSON.generate(run_id:ARGV.fetch(1)))',$Directory,$RunId)
  if($marker.ExitCode -ne 0){$errors.Add('WORKER_STOP_REQUEST_UNVERIFIED')}
  foreach($container in @($known|Where-Object{$_ -in $Containers})){
    $inspectArgs=@('inspect','--format','{{index .Config.Labels "jrc.task"}}|{{.State.Running}}',$container)
    $before=Invoke-BrokerHttpsCleanupCommand $Runner $inspectArgs
    $parts=([string]$before.Output).Trim() -split '\|'
    if($before.ExitCode -ne 0 -or $parts.Count -ne 2 -or $parts[0] -ne $Label){
      $errors.Add("CONTAINER_IDENTITY_UNVERIFIED:$container");continue
    }
    if($parts[1] -eq 'true'){
      $stop=Invoke-BrokerHttpsCleanupCommand $Runner @('stop','--time','10',$container)
      if($stop.ExitCode -ne 0){$errors.Add("STOP_FAILED:$container")}
    }
    $after=Invoke-BrokerHttpsCleanupCommand $Runner $inspectArgs
    $stopped=$after.ExitCode -eq 0 -and ([string]$after.Output).Trim() -eq "$Label|false"
    if(-not $stopped){$errors.Add("CONTAINER_STOP_UNVERIFIED:$container")}
    $observed.Add([pscustomobject]@{Name=$container;Stopped=$stopped})
  }
  $running=Invoke-BrokerHttpsCleanupCommand $Runner @('ps','--filter',$filter,'--format','{{.Names}}')
  if($running.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$running.Output)){
    $errors.Add('RUNNING_CONTAINER_INVENTORY_UNVERIFIED')
  }
  $networks=Invoke-BrokerHttpsCleanupCommand $Runner @('network','ls','--filter',$filter,'--format','{{.Name}}')
  $networkNames=@(([string]$networks.Output -split '\r?\n')|Where-Object{$_ -ne ''})
  $ownedNetwork=$false
  if($networks.ExitCode -ne 0){$errors.Add('NETWORK_INVENTORY_UNVERIFIED')}
  elseif(@($networkNames|Where-Object{$_ -ne $Network}).Count){$errors.Add('UNEXPECTED_LABELED_NETWORK')}
  elseif($networkNames -contains $Network){
    $identity=Invoke-BrokerHttpsCleanupCommand $Runner @('network','inspect','--format','{{index .Labels "jrc.task"}}',$Network)
    $ownedNetwork=$identity.ExitCode -eq 0 -and ([string]$identity.Output).Trim() -eq $Label
    if(-not $ownedNetwork){$errors.Add('NETWORK_IDENTITY_UNVERIFIED')}
  }
  $railArgs=@('inspect','--format','{{json .NetworkSettings.Networks}}',$RailsContainer)
  $beforeRails=Invoke-BrokerHttpsCleanupCommand $Runner $railArgs
  try {
    if($beforeRails.ExitCode -ne 0){throw 'INSPECT_FAILED'}
    $parsed=$beforeRails.Output|ConvertFrom-Json
    if($null -eq $parsed -or $parsed -isnot [pscustomobject]){throw 'INVALID_NETWORK_INVENTORY'}
    $attached=@($parsed.PSObject.Properties.Name) -contains $Network
    if($attached -and $ownedNetwork){
      $disconnect=Invoke-BrokerHttpsCleanupCommand $Runner @('network','disconnect','--force',$Network,$RailsContainer)
      if($disconnect.ExitCode -ne 0){$errors.Add('NETWORK_DISCONNECT_FAILED')}
    }
  } catch {$errors.Add('RAILS_NETWORK_BEFORE_UNVERIFIED')}
  $afterRails=Invoke-BrokerHttpsCleanupCommand $Runner $railArgs
  $detached=$false
  try {
    if($afterRails.ExitCode -ne 0){throw 'INSPECT_FAILED'}
    $parsed=$afterRails.Output|ConvertFrom-Json
    if($null -eq $parsed -or $parsed -isnot [pscustomobject]){throw 'INVALID_NETWORK_INVENTORY'}
    $detached=@($parsed.PSObject.Properties.Name) -notcontains $Network
  } catch {$errors.Add('RAILS_NETWORK_AFTER_UNVERIFIED')}
  if(-not $detached){$errors.Add('RAILS_NETWORK_DETACH_UNVERIFIED')}
  [pscustomobject]@{Verified=($errors.Count -eq 0);Errors=@($errors.ToArray());Containers=@($observed.ToArray());RailsDetached=$detached}
}
function Complete-BrokerHttpsCleanup {
  [CmdletBinding()]
  param($Cleanup,$PrimaryFailure)
  if($null -eq $Cleanup -or -not $Cleanup.Verified){
    $message='HTTPS_LAB_CLEANUP_UNVERIFIED: '+($Cleanup.Errors -join ',')
    if($PrimaryFailure){Write-Warning $message}else{throw $message}
  }
  if($PrimaryFailure){throw $PrimaryFailure}
  'Cleanup verified: nonce-owned containers stopped and Rails detached; containers, volumes, DBs and private fixture files preserved.'
}
