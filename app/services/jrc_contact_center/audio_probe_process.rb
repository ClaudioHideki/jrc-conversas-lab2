# frozen_string_literal: true

require 'timeout'

# Only the child process group created here is stopped. No PID discovery or shared process is used.
class JrcContactCenter::AudioProbeProcess
  Result = Struct.new(:state, :output)
  MAX_SECONDS = 15
  MAX_OUTPUT = 8192
  ENVIRONMENT = { 'PATH' => '/usr/bin:/bin', 'LANG' => 'C', 'LC_ALL' => 'C' }.freeze

  def initialize(timeout: MAX_SECONDS)
    raise ArgumentError unless timeout.is_a?(Numeric) && timeout.positive? && timeout <= MAX_SECONDS

    @timeout = timeout
  end

  def call(arguments:, file: nil)
    return Result.new(:unavailable, nil) if file && !file.stat.file?

    reader, writer = IO.pipe
    file&.rewind
    options = spawn_options.merge(in: file || File::NULL, out: writer)
    executable, *parameters = arguments
    pid = Process.spawn(ENVIRONMENT, [executable, executable], *parameters, options)
    process = Process.detach(pid)
    writer.close
    result = Timeout.timeout(@timeout) { read_result(reader, process) }
  rescue Timeout::Error
    result = Result.new(:timeout, nil)
  rescue SystemCallError, IOError
    result = Result.new(:unavailable, nil)
  ensure
    finish_owned_process(pid, process, result)
    writer&.close unless writer&.closed?
    reader&.close unless reader&.closed?
  end

  private

  def spawn_options
    { pgroup: true, close_others: true, unsetenv_others: true, err: File::NULL,
      rlimit_as: [768 * 1024 * 1024, 768 * 1024 * 1024], rlimit_cpu: [MAX_SECONDS, MAX_SECONDS + 1] }
  end

  def read_result(output, process)
    data = output.read(MAX_OUTPUT + 1) || ''
    return Result.new(:output_limit, nil) if data.bytesize > MAX_OUTPUT
    return Result.new(:nonzero, nil) unless process.value.success?

    Result.new(:ok, data)
  end

  def stop_owned_group(pid)
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH
    nil
  end

  def finish_owned_process(pid, process, result)
    return unless pid

    pending = process.nil? || process.alive?
    stop_owned_group(pid) if pending && result&.state != :ok
    process ? process.join : Process.waitpid(pid)
  rescue Errno::ECHILD
    nil
  end
end
