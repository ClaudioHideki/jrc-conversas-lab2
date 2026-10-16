require 'rails_helper'
require 'tmpdir'
require 'open3'
require 'timeout'

RSpec.describe JrcFlows::OwnershipHeartbeat do
  self.use_transactional_tests = false

  around do |example|
    Dir.mktmpdir('jrc-ownership-runtime-') do |directory|
      @runtime = Pathname.new(directory)
      @artifact = @runtime.join('artifact')
      @reports = @runtime.join('heartbeat')
      @challenges = @runtime.join('challenge')
      FileUtils.mkdir_p([@artifact.join('app'), @artifact.join('config'), @artifact.join('script'), @reports, @challenges])
      File.write(@artifact.join('app/payload.rb'), '# installed payload')
      File.write(@artifact.join('.git_sha'), 'a' * 40)
      File.write(
        @artifact.join('config/jrc_flow_ownership_guards.json'),
        JSON.generate('files' => {
                        'app/payload.rb' => Digest::SHA256.file(@artifact.join('app/payload.rb')).hexdigest
                      })
      )
      FileUtils.cp(Rails.root.join('script/jrc_flow_ownership_probe.rb'), @artifact.join('script'))
      @reports.chmod(0o700)
      example.run
    end
  end

  def challenge(nonce: 'n' * 43, issued_at: nil, expires_at: nil, directory: @challenges)
    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    File.write(directory.join('challenge.json'), JSON.generate(nonce: nonce, issuedAt: (issued_at || (now - 1.second)).utc.iso8601(6),
                                                               expiresAt: (expires_at || (now + 20.seconds)).utc.iso8601(6)))
  end

  def reporter(role: 'rails')
    described_class.new(root: @artifact, directory: @reports, role: role, challenge_directory: @challenges)
  end

  it 'measures the current PID, SQL time and loaded guards without creating a signature' do
    challenge
    report = reporter.write!
    expect(report).to include(nonce: 'n' * 43, pid: Process.pid, role: 'rails', loadedHooks: true)
    expect(report[:startTicks]).to eq(File.read('/proc/self/stat').split(') ', 2).last.split.fetch(19))
    expect(report[:namespace]).to eq(File.readlink('/proc/self/ns/pid'))
    expect(Time.iso8601(report[:observedAt])).to be <= ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    expect(JSON.parse(File.read(@reports.join("#{Process.pid}.json")))).not_to have_key('signature')
    expect(Dir.glob(@runtime.join('**/*attestation*').to_s)).to be_empty
  end

  it 'reads challenges only from the separate observation channel and rejects an expired nonce' do
    challenge(directory: @reports)
    expect { reporter.write! }.to raise_error(Errno::ENOENT)
    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    challenge(issued_at: now - 20.seconds, expires_at: now - 1.second)
    expect(reporter.write!).to be_nil
    expect(@reports.join("#{Process.pid}.json")).not_to exist
    expect { described_class.new(root: @artifact, directory: @reports, role: 'rails', challenge_directory: @reports) }.to raise_error(ArgumentError)
  end

  it 'refuses a changed artifact and an ancestor symlink escaping the artifact root' do
    challenge
    live = reporter
    live.write!
    Dir.mktmpdir('jrc-runtime-escaped-') do |outside|
      FileUtils.mv(@artifact.join('app'), File.join(outside, 'app'))
      File.symlink(File.join(outside, 'app'), @artifact.join('app'))
      expect { live.write! }.to raise_error(ArgumentError)
    end
  end

  it 'lets application startup proceed without an initial observation' do
    with_modified_env(JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR: nil, JRC_FLOW_OWNERSHIP_ATTESTATION_DIR: nil) do
      expect(Thread).not_to receive(:new)
      expect { described_class.start!(role: 'rails') }.not_to raise_error
    end
  end

  it 'probes a live forked worker using its own PID and process start ticks' do
    challenge
    ActiveRecord::Base.connection_handler.clear_all_connections!
    reader, writer = IO.pipe
    child = Process.fork do
      reader.close
      $PROGRAM_NAME = 'sidekiq ownership-probe-spec'
      report = reporter(role: 'worker').write!
      writer.write(JSON.generate(report) + "\n")
      writer.close
      sleep 20
      exit! 0
    end
    writer.close
    report = JSON.parse(Timeout.timeout(10) { reader.gets })
    expect(report).to include('pid' => child, 'role' => 'worker', 'loadedHooks' => true)
    output, error, status = Open3.capture3({
                                             'JRC_FLOW_OWNERSHIP_HEARTBEAT_DIR' => @reports.to_s,
                                             'JRC_FLOW_OWNERSHIP_CHALLENGE_DIR' => @challenges.to_s
                                           }, RbConfig.ruby, @artifact.join('script/jrc_flow_ownership_probe.rb').to_s, '--nonce', 'n' * 43)
    expect(status.success?).to be(true), error
    measured = JSON.parse(output).fetch('processes').find { |process| process['pid'] == child }
    expect(measured).to include('role' => 'worker', 'startTicks' => report.fetch('startTicks'))
    expect(measured.fetch('heartbeat')).to include('nonce' => 'n' * 43, 'pid' => child, 'loadedHooks' => true)
  ensure
    reader&.close
    writer&.close unless writer&.closed?
    Process.kill('TERM', child) if child
    Process.wait(child) if child
  end
end
