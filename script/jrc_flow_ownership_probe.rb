require 'json'
require 'digest'
require 'time'
require 'fileutils'
require 'securerandom'
require 'pathname'

# Run only by the external observer through Docker exec. No Rails runner is
# spawned: process measurements refer to the existing Puma/Sidekiq PIDs.
root = Pathname.new(__dir__).parent.realpath
contained_file = lambda do |relative|
  target = root.join(relative).cleanpath.realpath
  raise 'FLOW_GUARD_PATH' unless target.to_s.start_with?(root.to_s + '/') && target.file?

  target
end
directory = Pathname.new(ENV.fetch('JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR'))
raise 'FLOW_HEARTBEAT_DIRECTORY' unless directory.absolute? && !directory.symlink?

FileUtils.mkdir_p(directory, mode: 0o700)
raise 'FLOW_HEARTBEAT_PERMISSIONS' unless (directory.stat.mode & 0o022).zero?

operation, nonce = ARGV
raise 'FLOW_OBSERVER_NONCE' unless /\A[A-Za-z0-9_-]{43}\z/.match?(nonce.to_s) && ARGV.size == 2 && operation == '--nonce'

challenge_directory = Pathname.new(ENV.fetch('JRC_FLOW_OWNERSHIP_CHALLENGE_DIR')).realpath
raise 'FLOW_OBSERVER_CHALLENGE_CHANNEL' if challenge_directory == directory.realpath
raise 'FLOW_OBSERVER_CHALLENGE_CHANGED' unless JSON.parse(File.read(challenge_directory.join('challenge.json'))).fetch('nonce') == nonce

raise 'FLOW_OBSERVER_OPERATION' unless operation == '--nonce'

bytes = File.binread(contained_file.call('config/jrc_flow_ownership_guards.json'))
manifest = JSON.parse(bytes)
files = manifest.fetch('files').to_h do |relative, _expected|
  target = contained_file.call(relative)
  [relative, Digest::SHA256.file(target).hexdigest]
end
candidates = Dir.glob('/proc/[0-9]*/cmdline').filter_map do |file|
  command = File.binread(file).tr("\0", ' ')
  next unless /sidekiq|puma|rails (s|server)\b/.match?(command)

  pid = file.split('/')[2].to_i
  next if pid == Process.pid

  [pid, command]
rescue Errno::ENOENT, Errno::EACCES
  nil
end
cluster = candidates.any? { |_pid, command| command.include?('puma: cluster worker') }
processes = candidates.filter_map do |pid, command|
  next if cluster && command.include?('puma') && !command.include?('puma: cluster worker')

  ticks = File.read("/proc/#{pid}/stat").split(') ', 2).last.split.fetch(19)
  heartbeat = begin JSON.parse(File.read(directory.join("#{pid}.json"))); rescue Errno::ENOENT, JSON::ParserError; nil; end
  { pid: pid, startTicks: ticks, namespace: File.readlink("/proc/#{pid}/ns/pid"),
    role: command.include?('sidekiq') ? 'worker' : 'rails', heartbeat: heartbeat }
rescue Errno::ENOENT, Errno::EACCES
  nil
end
puts JSON.generate({ sourceSha: File.read(contained_file.call('.git_sha')).strip, guardManifestSha256: Digest::SHA256.hexdigest(bytes),
                     files: files, processes: processes })
