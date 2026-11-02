#requires -Version 7.2
param(
  [Parameter(Mandatory)][string]$BrokerImage,
  [Parameter(Mandatory)][string]$ImageIdentityPath,
  [Parameter(Mandatory)][string]$BrokerSourceSha,
  [Parameter(Mandatory)][string]$BrokerRoot,
  [Parameter(Mandatory)][string]$Lab2Root,
  [Parameter(Mandatory)][string]$OutputRoot,
  [string]$RailsContainer = 'jrc-lab2-durable-rails-20261102',
  [switch]$Execute
)
$ErrorActionPreference = 'Stop'
if (-not $Execute -or $env:BROKER_HTTPS_EXECUTE -ne '1') { throw 'Explicit BROKER_HTTPS_EXECUTE=1 and -Execute are required; this starts a laboratory stack.' }
if ($BrokerImage -notmatch '@sha256:[a-f0-9]{64}$') { throw 'The API image must be pinned by registry digest.' }
if (-not $IsWindows) { throw 'This orchestrator targets the authorized Windows Docker laboratory.' }
$BrokerRoot = (Resolve-Path -LiteralPath $BrokerRoot).Path
$Lab2Root = (Resolve-Path -LiteralPath $Lab2Root).Path
$scriptRoot = Join-Path $Lab2Root 'spec/homologation'
. (Join-Path $scriptRoot 'broker_https_cleanup.ps1')
$schemaPath = Join-Path $Lab2Root 'db/schema.rb'
if ((Get-Content -LiteralPath $schemaPath -Raw) -notmatch 'define\(version: 2026_11_02_110000\)') { throw 'Reviewed host schema110000 is required.' }
if ($scriptRoot.Contains(',') -or $BrokerRoot.Contains(',')) { throw 'Docker bind paths containing commas are not supported.' }

function Invoke-Docker([string[]]$DockerArguments) {
  $result = & docker @DockerArguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Docker laboratory operation failed: $($result -join [Environment]::NewLine)" }
  return ($result -join [Environment]::NewLine)
}
function Write-PublicLog([string]$Name, [string]$Value) {
  [IO.File]::WriteAllText((Join-Path $evidenceDirectory $Name), $Value, [Text.UTF8Encoding]::new($false))
}
function New-FixtureSecret {
  $bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
  [Convert]::ToHexString($bytes).ToLowerInvariant()
}
function Get-LabExecArguments([string]$Key) {
  $redisDatabase = if ($Key -eq 'a') { 0 } else { 1 }
  @('exec','-w','/lab2-current-20261102',
    '-e','RAILS_ENV=test','-e',"POSTGRES_DATABASE=jrc_broker_https_${Key}_test",
    '-e','POSTGRES_HOST=broker-https-rails-postgres','-e','POSTGRES_USERNAME=postgres','-e',"POSTGRES_PASSWORD=$railsPgPassword",
    '-e',"REDIS_URL=redis://broker-https-redis:6379/$redisDatabase",'-e','REDIS_PASSWORD=','-e','REDIS_SENTINELS=',
    '-e','HTTP_PROXY=','-e','HTTPS_PROXY=','-e','ALL_PROXY=','-e','http_proxy=','-e','https_proxy=','-e','all_proxy=',
    '-e','NO_PROXY=broker-https-lab.test','-e','no_proxy=broker-https-lab.test',
    '-e','BROKER_HTTPS_LAB=1','-e',"BROKER_HTTPS_DIRECTORY=$containerDirectory",
    '-e','BROKER_HTTPS_ORIGIN=https://broker-https-lab.test','-e','SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true',
    '-e',"SSL_CERT_FILE=$containerDirectory/ca.pem",'-e','JRC_BROKER_ENABLED=true',
    '-e','JRC_BROKER_ALLOWED_ORIGINS=https://broker-https-lab.test','-e',"JRC_BROKER_CREDENTIAL_KEY=$credentialKey",
    '-e',"FRONTEND_URL=https://lab2-${Key}.example.test")
}
function Invoke-LabPhase([string]$Key,[string]$Phase) {
  $arguments = (Get-LabExecArguments $Key) + @($RailsContainer,'bundle','exec','rails','runner','spec/homologation/broker_https_control.rb',$Phase)
  Write-PublicLog "${Phase}_${Key}.log" (Invoke-Docker $arguments)
}
function Copy-IntoRails([string]$Source,[string]$Name) {
  $null = Invoke-Docker @('cp',$Source,"${RailsContainer}:${containerDirectory}/$Name")
}
function Copy-FromRails([string]$Name,[string]$Destination) {
  $null = Invoke-Docker @('cp',"${RailsContainer}:${containerDirectory}/$Name",$Destination)
}
function Read-WorkerJson([string]$Name) {
  $value = & docker exec $RailsContainer cat "${containerDirectory}/$Name" 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return (($value -join [Environment]::NewLine) | ConvertFrom-Json)
}
function Wait-WorkerFile([string]$Key,[string]$Suffix,[string]$State,$WorkerProcess) {
  $deadline = [DateTime]::UtcNow.AddMinutes(4)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Read-WorkerJson "worker_${Key}_error.json") { throw "Worker $Key reported a fixture error; inspect its private laboratory log." }
    $value = Read-WorkerJson "worker_${Key}_${Suffix}.json"
    if ($value -and ($State -eq '' -or $value.state -eq $State)) { return $value }
    $WorkerProcess.Refresh()
    if ($WorkerProcess.HasExited) { throw "Worker $Key exited $($WorkerProcess.ExitCode) before $Suffix/$State; inspect its private fixture log." }
    Start-Sleep -Milliseconds 250
  }
  throw "Timed out waiting for worker $Key/$Suffix/$State."
}
function Start-LabWorker([string]$Key,[string]$StopAt,[bool]$KillArmed) {
  $arguments = (Get-LabExecArguments $Key) + @('-e',"BROKER_HTTPS_STOP_AT=$StopAt",'-e',"BROKER_HTTPS_KILL_ARMED=$([int]$KillArmed)",
    $RailsContainer,'bundle','exec','ruby','spec/homologation/broker_https_worker.rb')
  $outFile = Join-Path $privateDirectory "docker_worker_${Key}_${StopAt}_${KillArmed}.out"
  $errFile = Join-Path $privateDirectory "docker_worker_${Key}_${StopAt}_${KillArmed}.err"
  # All native arguments are generated fixture identifiers without whitespace or shell metacharacters.
  return Start-Process -FilePath (Get-Command docker).Source -ArgumentList $arguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
}
function Wait-LabWorkerExit($Process,[int]$ExpectedCode) {
  if (-not $Process.WaitForExit(240000)) { throw 'The explicitly launched worker did not exit within the laboratory deadline.' }
  $Process.Refresh()
  if ($Process.ExitCode -ne $ExpectedCode) { throw "Worker exited $($Process.ExitCode), expected $ExpectedCode." }
}
function Invoke-ProxyControl([string]$Operation,[string]$Key='a') {
  return Invoke-Docker @('exec',$proxyContainer,'node','/app/spec/homologation/broker_https_proxy.mjs','control',$Operation,$Key)
}
function Wait-ProxyControl([string]$Operation) {
  $deadline = [DateTime]::UtcNow.AddSeconds(90)
  do {
    try { $null = Invoke-ProxyControl $Operation 'a'; return } catch { Start-Sleep -Milliseconds 500 }
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Fixture proxy/Broker readiness failed: $Operation"
}
function Wait-Postgres([string]$ContainerName) {
  $deadline = [DateTime]::UtcNow.AddSeconds(90)
  do {
    $null = & docker exec $ContainerName pg_isready -U postgres 2>$null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Milliseconds 500
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Fixture PostgreSQL did not start: $ContainerName"
}

$railsInfo = (Invoke-Docker @('inspect',$RailsContainer) | ConvertFrom-Json)[0]
if ($railsInfo.Config.Labels.'jrc.task' -ne 'durable-20261102') { throw 'The approved materialized Rails laboratory was not found.' }
if (@($railsInfo.NetworkSettings.Networks.PSObject.Properties.Name | Where-Object { $_ -like 'jrc-broker-https-*' }).Count) {
  throw 'Rails is already attached to another HTTPS fixture. Preserve/review it before explicitly disconnecting it.'
}
$pgInfo = (Invoke-Docker @('inspect','jrc-lab2-durable-pg-20261102') | ConvertFrom-Json)[0]
$redisInfo = (Invoke-Docker @('inspect','jrc-lab2-durable-redis-20261102') | ConvertFrom-Json)[0]
if ($pgInfo.Config.Labels.'jrc.task' -ne 'durable-20261102' -or $redisInfo.Config.Labels.'jrc.task' -ne 'durable-20261102') { throw 'Unexpected image source for fixture PG/Redis.' }
$null = Invoke-Docker @('pull',$BrokerImage)
$imageInfo = (Invoke-Docker @('image','inspect',$BrokerImage) | ConvertFrom-Json)[0]
$approvedIdentity = Get-Content -LiteralPath $ImageIdentityPath -Raw | ConvertFrom-Json
$platformInfo = (Invoke-Docker @('image','inspect','--platform','linux/amd64',$BrokerImage) | ConvertFrom-Json)[0]
$platformReference = ($BrokerImage -split '@')[0] + '@' + $approvedIdentity.platformDigest
$platformManifest = Invoke-Docker @('buildx','imagetools','inspect','--raw',$platformReference) | ConvertFrom-Json
if ($approvedIdentity.component -ne 'api' -or $approvedIdentity.indexDigest -ne ($BrokerImage -split '@')[1] -or
    $platformInfo.Descriptor.digest -ne $approvedIdentity.platformDigest -or
    $platformManifest.config.digest -ne $approvedIdentity.expectedImageId) {
  throw 'Pulled index/platform/config identity differs from the reviewed immutable release artifact.'
}
if ($BrokerSourceSha -notmatch '^[a-f0-9]{40}$') { throw 'Explicit source revision from reviewed release evidence is required.' }
$sourceSha = $BrokerSourceSha
$labelSourceSha = $platformInfo.Config.Labels.'org.opencontainers.image.revision'
if ($labelSourceSha -and $labelSourceSha -ne $sourceSha) { throw 'Image source label contradicts reviewed release evidence.' }
$criticalFiles = @('app/models/message.rb','app/models/jrc_broker_webhook_obligation.rb',
  'app/jobs/jrc_broker/webhook_obligation_job.rb','app/jobs/jrc_broker/webhook_recovery_job.rb',
  'app/services/jrc_broker/webhook_delivery.rb','app/services/jrc_broker/webhook_diagnostic.rb',
  'lib/webhooks/trigger.rb','lib/safe_fetch.rb','lib/safe_fetch/request_options.rb',
  'lib/safe_fetch/private_network_request.rb','lib/safe_fetch/fetcher.rb')
$digestProgram = 'require "digest"; require "json"; puts JSON.generate(ARGV.to_h { |path| [path,Digest::SHA256.hexdigest(File.binread(path).gsub("\r\n","\n"))] })'
$runtimeDigests = (Invoke-Docker (@('exec','-w','/lab2-current-20261102',$RailsContainer,'ruby','-e',$digestProgram) + $criticalFiles)) | ConvertFrom-Json -AsHashtable
foreach ($relativePath in $criticalFiles) {
  $content = [IO.File]::ReadAllText((Join-Path $Lab2Root $relativePath)).Replace("`r`n","`n")
  $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content))).ToLowerInvariant()
  if ($runtimeDigests[$relativePath] -ne $digest) { throw "Reviewed LAB2 source differs from materialized runtime: $relativePath. Coordinate an explicit source sync first." }
}
$harnessSourceRevision = (& git -C $Lab2Root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'HARNESS_SOURCE_REVISION_UNVERIFIED'}
$harnessHashes = @{}
foreach($file in Get-ChildItem -LiteralPath $scriptRoot -Filter 'broker_https_*' -File){
  $relativePath="spec/homologation/$($file.Name)"
  $headBlob=(& git -C $Lab2Root rev-parse "HEAD:$relativePath" 2>$null)
  if($LASTEXITCODE -ne 0){throw "HARNESS_SOURCE_NOT_COMMITTED:$relativePath"}
  $workingBlob=(& git -C $Lab2Root hash-object "--path=$relativePath" $file.FullName)
  if($LASTEXITCODE -ne 0 -or $headBlob -ne $workingBlob){throw "HARNESS_SOURCE_DIFFERS_FROM_COMMIT:$relativePath"}
  $content=[IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n")
  $harnessHashes[$relativePath]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content))).ToLowerInvariant()
}

$runId = [Guid]::NewGuid().ToString()
$resourcePrefix = 'jrc-broker-https-' + $runId.Substring(0,8)
$label = "broker-https-$runId"
$containerDirectory = "/tmp/broker_https_$runId"
$privateDirectory = Join-Path ([IO.Path]::GetTempPath()) "broker_https_$runId"
$evidenceDirectory = Join-Path $OutputRoot "broker-https-$runId"
$null = New-Item -ItemType Directory -Path $privateDirectory,$evidenceDirectory
Write-PublicLog 'lab2-runtime-source.json' ($runtimeDigests | ConvertTo-Json -Depth 4)
Write-PublicLog 'harness-source.json' (@{revision=$harnessSourceRevision;committed_content_verified=$true;sha256_lf=$harnessHashes}|ConvertTo-Json -Depth 5)
$privateAcl = Get-Acl -LiteralPath $privateDirectory
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$privateAcl.SetAccessRuleProtection($true,$false)
$privateAcl.SetOwner($currentSid)
$privateAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($currentSid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
$privateAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-18'),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
Set-Acl -LiteralPath $privateDirectory -AclObject $privateAcl
$railsPgPassword = New-FixtureSecret
$brokerPgPassword = New-FixtureSecret
$credentialKey = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$brokerPg = "$resourcePrefix-broker-pg"; $railsPg = "$resourcePrefix-rails-pg"
$redisContainer = "$resourcePrefix-redis"; $seedContainer = "$resourcePrefix-seed"
$apiContainer = "$resourcePrefix-api"; $proxyContainer = "$resourcePrefix-proxy"
$primaryFailure = $null
$cleanup = $null
try {
$null = Invoke-Docker @('network','create','--internal','--label',"jrc.task=$label",$resourcePrefix)
$null = Invoke-Docker @('network','connect',$resourcePrefix,$RailsContainer)
foreach ($item in @(@($brokerPg,'broker-https-postgres',$brokerPgPassword),@($railsPg,'broker-https-rails-postgres',$railsPgPassword))) {
  $null = Invoke-Docker @('run','--detach','--name',$item[0],'--network',$resourcePrefix,'--network-alias',$item[1],
    '--label',"jrc.task=$label",'-e',"POSTGRES_PASSWORD=$($item[2])",'--mount',"type=volume,source=$($item[0])-data,target=/var/lib/postgresql/data",$pgInfo.Image)
  Wait-Postgres $item[0]
}
$null = Invoke-Docker @('run','--detach','--name',$redisContainer,'--network',$resourcePrefix,'--network-alias','broker-https-redis',
  '--label',"jrc.task=$label",'--mount',"type=volume,source=$redisContainer-data,target=/data",$redisInfo.Image,'redis-server','--appendonly','yes')
$null = Invoke-Docker @('cp',"$scriptRoot/.","${RailsContainer}:/lab2-current-20261102/spec/homologation/")
$null = Invoke-Docker @('exec',$RailsContainer,'ruby','-rfileutils','-e','FileUtils.mkdir_p(ARGV.fetch(0), mode: 0700)',$containerDirectory)
$null = Invoke-Docker @('exec','-w','/lab2-current-20261102',$RailsContainer,'bundle','exec','ruby','spec/homologation/broker_https_certificates.rb',$containerDirectory)
$null = Invoke-Docker @('cp',"${RailsContainer}:${containerDirectory}/.",$privateDirectory)
Copy-IntoRails $schemaPath 'schema110000.rb'
foreach ($key in @('a','b')) {
  $executionArguments = (Get-LabExecArguments $key) + @('-e',"SCHEMA=$containerDirectory/schema110000.rb",$RailsContainer,'bundle','exec','rails','db:create','db:schema:load')
  Write-PublicLog "cold_schema_${key}.log" (Invoke-Docker $executionArguments)
  Invoke-LabPhase $key 'prepare'
  Copy-FromRails "participant_${key}.json" (Join-Path $privateDirectory "participant_${key}.json")
}
$settings = @{ fixture_only=$true; run_id=$runId; control_token=(New-FixtureSecret); broker_app_password=(New-FixtureSecret);
  integration_encryption_key=[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32));
  broker_admin_url="postgresql://postgres:${brokerPgPassword}@broker-https-postgres:5432/postgres";
  broker_image=$BrokerImage; broker_source_sha=$sourceSha }
[IO.File]::WriteAllText((Join-Path $privateDirectory 'settings.private.json'),($settings | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$nodeBase = @('--network',$resourcePrefix,'--label',"jrc.task=$label",'--platform','linux/amd64','--user','0:0','--cap-drop','ALL','--entrypoint','node',
  '-e','NODE_ENV=test','-e','BROKER_HTTPS_LAB=1','-e','BROKER_HTTPS_DIRECTORY=/fixture',
  '--mount',"type=bind,source=$scriptRoot,target=/app/spec/homologation,readonly",
  '--mount',"type=bind,source=$privateDirectory,target=/fixture",
  '--mount',"type=bind,source=$BrokerRoot/apps/api/tests/integration/helpers,target=/app/broker-test-helpers,readonly")
$seedArgs = @('run','--name',$seedContainer) + $nodeBase + @($BrokerImage,'/app/spec/homologation/broker_https_receiver.mjs','seed')
Write-PublicLog 'broker_seed.log' (Invoke-Docker $seedArgs)
Copy-IntoRails (Join-Path $privateDirectory 'manifest.json') 'manifest.json'
foreach ($key in @('a','b')) {
  Invoke-LabPhase $key 'commit'
  Copy-FromRails "participant_${key}.json" (Join-Path $privateDirectory "participant_${key}.json")
}
$manifest = Get-Content -LiteralPath (Join-Path $privateDirectory 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
$manifest.contexts = @('a','b' | ForEach-Object { Get-Content -LiteralPath (Join-Path $privateDirectory "participant_${_}.json") -Raw | ConvertFrom-Json -AsHashtable })
[IO.File]::WriteAllText((Join-Path $privateDirectory 'manifest.json'),($manifest | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Copy-IntoRails (Join-Path $privateDirectory 'manifest.json') 'manifest.json'
$proxyArgs = @('run','--detach','--name',$proxyContainer,'--network-alias','broker-https-lab.test','--cap-add','NET_BIND_SERVICE') + $nodeBase +
  @($BrokerImage,'/app/spec/homologation/broker_https_proxy.mjs','serve')
$null = Invoke-Docker $proxyArgs
Wait-ProxyControl 'ready'
# The actual Broker process is deliberately NOT started until committed obligations have failed once over real TLS.
foreach ($key in @('a','b')) {
  $workerProcess = Start-LabWorker $key 'pending' $false
  $null = Wait-WorkerFile $key 'done' 'pending' $workerProcess
  Wait-LabWorkerExit $workerProcess 0
}
$apiArgs = @('run','--detach','--name',$apiContainer,'--network-alias','broker-https-api') + $nodeBase +
  @($BrokerImage,'/app/spec/homologation/broker_https_receiver.mjs','serve')
$null = Invoke-Docker $apiArgs
Wait-ProxyControl 'health'
foreach ($mode in @('trusted','wrong-ca','wrong-hostname')) {
  $executionArguments = Get-LabExecArguments 'a'
  if ($mode -eq 'wrong-ca') { $executionArguments += @('-e',"SSL_CERT_FILE=$containerDirectory/wrong-ca.pem") }
  $executionArguments += @($RailsContainer,'bundle','exec','ruby','spec/homologation/broker_https_tls_probe.rb',$mode)
  Write-PublicLog "tls_${mode}.log" (Invoke-Docker $executionArguments)
}
Invoke-LabPhase 'a' 'foreign-signature'
$null = Invoke-ProxyControl 'arm' 'a'
Invoke-LabPhase 'a' 'recover'
$workerProcess = Start-LabWorker 'a' 'delivered' $true
$null = Wait-WorkerFile 'a' 'killed' 'running' $workerProcess
Wait-LabWorkerExit $workerProcess 137
Invoke-LabPhase 'b' 'recover'
$workerProcess = Start-LabWorker 'b' 'delivered' $false
$null = Wait-WorkerFile 'b' 'done' 'delivered' $workerProcess
Wait-LabWorkerExit $workerProcess 0
Invoke-LabPhase 'a' 'recover-crash'
$workerProcess = Start-LabWorker 'a' 'delivered' $false
$null = Wait-WorkerFile 'a' 'done' 'delivered' $workerProcess
Wait-LabWorkerExit $workerProcess 0
foreach ($key in @('a','b')) {
  Invoke-LabPhase $key 'verify'
  Copy-FromRails "proof_${key}.json" (Join-Path $evidenceDirectory "proof_${key}.json")
  Copy-FromRails "worker_${key}_done.json" (Join-Path $evidenceDirectory "worker_${key}_done.json")
}
Copy-FromRails 'worker_a_killed.json' (Join-Path $evidenceDirectory 'worker_a_killed.json')
Copy-FromRails 'foreign_signature.json' (Join-Path $evidenceDirectory 'foreign_signature.json')
[IO.File]::Copy((Join-Path $privateDirectory 'wire.jsonl'),(Join-Path $evidenceDirectory 'wire.jsonl'))
$result = @{ gate='LAB2_TLS_BROKER_DURABLE_CUSTODY'; broker_image=$BrokerImage; broker_source_sha=$sourceSha;
  harness_source_revision=$harnessSourceRevision; harness_source_committed_content_verified=$true; harness_sha256_lf=$harnessHashes;
  docker_store_image_id=$imageInfo.Id; broker_platform_digest=$platformInfo.Descriptor.digest;
  broker_config_digest=$platformManifest.config.digest; image_identity_artifact_sha256=(Get-FileHash -LiteralPath $ImageIdentityPath -Algorithm SHA256).Hash;
  source_attribution='reviewed release evidence; OCI source label may be absent';
  independent_lab2_consumers=2; same_real_local_ids=$true; redis_databases=@(0,1); stock_chatwoot_cclx_homologated=$false;
  sigkill_exit_code=137;
  physical_whatsapp_delivery='NOT_EXERCISED'; resource_prefix=$resourcePrefix;
  no_public_ports=$true; safe_fetch_real=$true; production_ssrf_unchanged=$true; fixture_allow_private_network=$true }
} catch {
  $primaryFailure = $_
} finally {
  $cleanupRunner = {
    param([string[]]$DockerArguments)
    $PSNativeCommandUseErrorActionPreference = $false
    $value = & docker @DockerArguments 2>&1
    $nativeExit = $LASTEXITCODE
    [pscustomobject]@{ExitCode=$nativeExit;Output=($value -join [Environment]::NewLine)}
  }
  try {
    $cleanup = Invoke-BrokerHttpsCleanup -Runner $cleanupRunner -Containers @($apiContainer,$proxyContainer,$seedContainer,$brokerPg,$railsPg,$redisContainer) `
      -Label $label -Network $resourcePrefix -RailsContainer $RailsContainer -Directory $containerDirectory -RunId $runId
  } catch {
    $cleanup = [pscustomobject]@{Verified=$false;Errors=@('CLEANUP_HELPER_FAILED');Containers=@();RailsDetached=$false}
  }
  try { Write-PublicLog 'cleanup-state.json' ($cleanup | ConvertTo-Json -Depth 5) }
  catch {
    $cleanup.Verified=$false
    $cleanup.Errors=@($cleanup.Errors)+@('CLEANUP_EVIDENCE_WRITE_FAILED')
  }
}
$cleanupSuccess = Complete-BrokerHttpsCleanup -Cleanup $cleanup -PrimaryFailure $primaryFailure
$result.cleanup_verified = $true
Write-PublicLog 'result.json' ($result | ConvertTo-Json -Depth 6)
Write-Output ($result | ConvertTo-Json -Depth 6)
Write-Output $cleanupSuccess
