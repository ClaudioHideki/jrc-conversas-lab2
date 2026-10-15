require 'digest'
require 'fileutils'
require 'json'
require 'pathname'
require 'time'

# Reports are measurements from this live PID. Only the external deployment
# observer signs them after independently checking Docker and /proc.
class JrcFlows::OwnershipHeartbeat
  HOOKS = {
    'JrcFlowsListener' => 'JrcFlows::OwnershipEntrypoints::Listener',
    'JrcFlows::DispatchJob' => 'JrcFlows::OwnershipEntrypoints::Dispatch',
    'JrcFlows::ResumeJob' => 'JrcFlows::OwnershipEntrypoints::Resume',
    'JrcFlows::RecoveryJob' => 'JrcFlows::OwnershipEntrypoints::Recovery',
    'JrcFlows::WorkflowTurnJob' => 'JrcFlows::OwnershipEntrypoints::WorkflowTurn',
    'JrcFlows::Runner' => 'JrcFlows::OwnershipEntrypoints::Runner',
    'JrcFlows::WorkflowRunner' => 'JrcFlows::OwnershipEntrypoints::WorkflowRunner',
    'JrcFlows::RemoteEventJob' => 'JrcFlows::OwnershipEntrypoints::RemoteEvent',
    'JrcFlows::RemoteResumeJob' => 'JrcFlows::OwnershipEntrypoints::RemoteResume',
    'JrcFlows::RemoteRecoveryJob' => 'JrcFlows::OwnershipEntrypoints::RemoteRecovery',
    'JrcFlows::RemoteRunner' => 'JrcFlows::OwnershipEntrypoints::RemoteRunner',
    'JrcFlows::Actions' => 'JrcFlows::OwnershipHooks::Actions',
    'JrcFlows::WorkflowEngine' => 'JrcFlows::OwnershipHooks::Workflow',
    'JrcFlows::ChatwootClient' => 'JrcFlows::OwnershipHooks::RemoteClient',
    'JrcFlows::Delivery' => 'JrcFlows::OwnershipHooks::Delivery',
    'JrcRelationship::PlaybookFlowWebhookDelivery' => 'JrcFlows::OwnershipHooks::PlaybookWebhook',
    'JrcRelationship::PlaybookFlowResumeJob' => 'JrcFlows::OwnershipEntrypoints::PlaybookResume',
    'AutomationRules::ActionService' => 'JrcFlows::NativeResponderHooks::Rules',
    'SendReplyJob' => 'JrcFlows::NativeResponderHooks::Replies',
    'WebhookJob' => 'JrcFlows::NativeResponderHooks::MessageWebhooks',
    'AgentBotListener' => 'JrcFlows::NativeResponderHooks::BotListener',
    'AgentBots::WebhookJob' => 'JrcFlows::NativeResponderHooks::BotWebhook',
    'Api::V1::Accounts::Conversations::MessagesController' => 'JrcFlows::NativeResponderHooks::MessageActor',
    'Api::V1::Accounts::Conversations::AssignmentsController' => 'JrcFlows::NativeResponderHooks::AssignmentActor',
    'Api::V1::Accounts::ConversationsController' => 'JrcFlows::NativeResponderHooks::ConversationActor'
  }.freeze

  def self.start!(role:)
    directory = ENV.fetch('JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR', nil)
    return if directory.to_s.empty?
    return if @pid == Process.pid && @thread&.alive?

    @pid = Process.pid
    @thread = Thread.new do
      Thread.current.name = 'jrc-flow-ownership-heartbeat'
      reporter = new(root: Rails.root, directory: directory, role: role)
      loop do
        begin
          Rails.application.executor.wrap { reporter.write! }
        rescue StandardError => e
          Rails.logger.warn("Flow ownership heartbeat unavailable: #{e.class.name}")
        end
        sleep 5
      end
    end
  end

  def self.stop!
    @thread&.kill
    @thread = nil
  end

  def initialize(root:, directory:, role:, challenge_directory: ENV.fetch('JRC_FLOW_OWNERSHIP_CHALLENGE_DIR'))
    raise ArgumentError unless %w[rails worker].include?(role)

    @root = Pathname.new(root).realpath
    @directory = Pathname.new(directory)
    @role = role
    @challenge_directory = Pathname.new(challenge_directory).realpath
    raise ArgumentError unless @directory.absolute?

    FileUtils.mkdir_p(@directory, mode: 0o700)
    raise ArgumentError if @directory.symlink? || (@directory.stat.mode & 0o022).positive?
    raise ArgumentError if @directory.realpath == @challenge_directory
  end

  def write!
    now = ApplicationRecord.connection_pool.with_connection { |db| db.select_value('SELECT clock_timestamp()').to_time }
    challenge = JSON.parse(File.read(@challenge_directory.join('challenge.json')))
    return unless /\A[A-Za-z0-9_-]{43}\z/.match?(challenge['nonce'].to_s)
    return unless Time.iso8601(challenge.fetch('issuedAt')) <= now && Time.iso8601(challenge.fetch('expiresAt')) > now
    return unless Time.iso8601(challenge.fetch('expiresAt')) <= Time.iso8601(challenge.fetch('issuedAt')) + 30

    manifest_bytes = File.binread(contained_file('config/jrc_flow_ownership_guards.json'))
    manifest = JSON.parse(manifest_bytes)
    source = File.read(contained_file('.git_sha')).strip
    raise ArgumentError unless /\A[a-f0-9]{40}\z/.match?(source)

    actual = manifest.fetch('files').to_h do |relative, expected|
      target = contained_file(relative)
      hash = Digest::SHA256.file(target).hexdigest
      raise ArgumentError unless hash == expected

      [relative, hash]
    end
    seal = [source, Digest::SHA256.hexdigest(manifest_bytes), actual]
    @boot_seal ||= seal
    raise ArgumentError unless @boot_seal == seal
    raise ArgumentError unless HOOKS.all? { |target, hook| target.constantize.ancestors.include?(hook.constantize) }

    JrcFlows::NativeResponders.installed!

    pid = Process.pid
    ticks = File.read('/proc/self/stat').split(') ', 2).last.split.fetch(19)
    report = { nonce: challenge.fetch('nonce'), pid: pid, startTicks: ticks, namespace: File.readlink('/proc/self/ns/pid'),
               role: @role, sourceSha: source, guardManifestSha256: seal[1], loadedHooks: true, observedAt: now.utc.iso8601(6) }
    temporary = @directory.join(".#{pid}-#{SecureRandom.hex(8)}")
    File.write(temporary, JSON.generate(report), mode: 'wx', perm: 0o600)
    File.rename(temporary, @directory.join("#{pid}.json"))
    report
  end

  private

  def contained_file(relative)
    target = @root.join(relative).cleanpath.realpath
    raise ArgumentError unless target.to_s.start_with?(@root.to_s + '/') && target.file?

    target
  end
end
