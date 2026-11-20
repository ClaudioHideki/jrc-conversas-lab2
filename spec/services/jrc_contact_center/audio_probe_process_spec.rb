require 'rails_helper'

RSpec.describe JrcContactCenter::AudioProbeProcess do
  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && RUBY_PLATFORM.include?('linux')
    raise 'Audio subprocess tests require the exclusively owned disposable Linux runner' unless owned
  end

  it 'returns bounded ordinary output from its own command without a shell' do
    result = described_class.new.call(arguments: ['/usr/bin/printf', '%s', 'SYNTHETIC media probe'])
    expect(result.state).to eq(:ok)
    expect(result.output).to eq('SYNTHETIC media probe')
  end

  it 'does not inherit application credentials or arbitrary environment into the child' do
    with_modified_env JRC_SYNTHETIC_PRIVATE_CANARY: 'synthetic-value-not-a-credential' do
      result = described_class.new.call(arguments: ['/usr/bin/env'])
      expect(result.state).to eq(:ok)
      expect(result.output).not_to include('JRC_SYNTHETIC_PRIVATE_CANARY', 'synthetic-value-not-a-credential')
      expect(result.output.lines.map { |line| line.split('=').first }.sort).to eq(%w[LANG LC_ALL PATH])
    end
  end

  it 'marks a missing executable unavailable without exposing arguments or system paths in output' do
    result = described_class.new.call(arguments: ['/nonexistent/jrc-synthetic-audio-probe'])
    expect(result.state).to eq(:unavailable)
    expect(result.output).to be_nil
  end

  it 'does not approve empty output from a failed command' do
    expect(Process).not_to receive(:kill)
    result = described_class.new.call(arguments: ['/usr/bin/false'])
    expect(result.state).to eq(:nonzero)
    expect(result.output).to be_nil
  end

  it 'treats a single argument containing shell syntax as an executable name instead of invoking a shell' do
    result = described_class.new.call(arguments: ['/usr/bin/printf SYNTHETIC; /usr/bin/true'])
    expect(result.state).to eq(:unavailable)
    expect(result.output).to be_nil
  end

  it 'terminates only its owned group when bounded stdout is exceeded' do
    result = described_class.new.call(arguments: ['/usr/bin/head', '-c', '9000', '/dev/zero'])
    expect(result.state).to eq(:output_limit)
    expect(result.output).to be_nil
  end

  it 'terminates its owned sleeping child at the wall timeout' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = described_class.new(timeout: 0.2).call(arguments: ['/usr/bin/sleep', '10'])
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(result.state).to eq(:timeout)
    expect(result.output).to be_nil
    expect(elapsed).to be < 5
  end

  it 'does not allow a caller to increase the maximum wall timeout' do
    expect { described_class.new(timeout: described_class::MAX_SECONDS + 1) }.to raise_error(ArgumentError)
  end

  it 'inherits only the owned regular input descriptor without putting its path in command arguments' do
    Tempfile.create('jrc-synthetic-audio-descriptor') do |file|
      file.write('SYNTHETIC owned descriptor')
      file.flush
      result = described_class.new.call(arguments: ['/usr/bin/head', '-c', '9'], file: file)
      expect(result.state).to eq(:ok)
      expect(result.output).to eq('SYNTHETIC')
      expect(file).not_to be_closed
    end
  end

  it 'refuses a pipe as media input rather than reading a shared or unbounded nonregular descriptor' do
    IO.pipe do |reader, writer|
      result = described_class.new.call(arguments: ['/usr/bin/head', '-c', '9'], file: reader)
      expect(result.state).to eq(:unavailable)
      expect(result.output).to be_nil
      expect(reader).not_to be_closed
      expect(writer).not_to be_closed
    end
  end
end
