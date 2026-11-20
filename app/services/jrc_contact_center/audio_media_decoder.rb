# frozen_string_literal: true

# Decoding proves media readability, never antivirus clearance or permission to publish.
class JrcContactCenter::AudioMediaDecoder
  BINARY = '/usr/bin/ffmpeg'
  FORMATS = 'wav,mp3,ogg,mov,matroska,webm'.freeze

  def identity
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-version'])
    return unless result.state == :ok

    version = result.output.lines.first.to_s.strip.first(200)
    version if version.start_with?('ffmpeg version ') && fd_available?
  end

  def call(file)
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: arguments, file: file)
    return decoded_progress?(result.output) ? 'valid' : 'invalid' if result.state == :ok

    result.state == :nonzero ? 'invalid' : 'unavailable'
  end

  private

  def decoded_progress?(output)
    final_time = output.scan(/^out_time_us=([0-9]{1,19})$/).last&.first
    output.end_with?("progress=end\n") && final_time && final_time.to_i.positive?
  end

  def fd_available?
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-protocols'])
    result.state == :ok && result.output.split('Output:').first.lines.map(&:strip).include?('fd')
  end

  def arguments
    [BINARY, '-nostdin', '-v', 'error', '-xerror', '-err_detect', 'explode', '-max_alloc', '67108864', '-progress', 'pipe:1', '-nostats',
     '-protocol_whitelist', 'fd', '-format_whitelist', FORMATS, '-max_streams', '1', '-threads', '1',
     '-i', 'fd:', '-map', '0:a:0', '-threads', '1', '-f', 'null', '-']
  end
end
