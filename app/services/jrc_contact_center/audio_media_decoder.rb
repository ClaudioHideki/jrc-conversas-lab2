# frozen_string_literal: true

# Decoding proves media readability, never antivirus clearance or permission to publish.
class JrcContactCenter::AudioMediaDecoder
  BINARY = '/usr/bin/ffmpeg'
  FORMATS = 'wav,mp3,ogg,mov,matroska,webm'
  EMPTY_PCM_SHA256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'

  def identity
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-version'])
    return unless result.state == :ok

    version = result.output.lines.first.to_s.strip.first(200)
    version if version.start_with?('ffmpeg version ') && fd_available?
  end

  def call(file)
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: arguments, file: file)
    return decoded_frames?(result.output) ? 'valid' : 'invalid' if result.state == :ok

    result.state == :nonzero ? 'invalid' : 'unavailable'
  end

  private

  def decoded_frames?(output)
    hash = output.match(/\ASHA256=([0-9a-f]{64})\n\z/)&.captures&.first
    hash.present? && hash != EMPTY_PCM_SHA256
  end

  def fd_available?
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-protocols'])
    result.state == :ok && result.output.split('Output:').first.lines.map(&:strip).include?('fd')
  end

  def arguments
    [BINARY, '-nostdin', '-v', 'error', '-xerror', '-err_detect', 'explode', '-max_alloc', '67108864', '-nostats',
     '-protocol_whitelist', 'fd', '-format_whitelist', FORMATS, '-max_streams', '1', '-threads', '1',
     '-i', 'fd:', '-map', '0:a:0', '-threads', '1', '-c:a', 'pcm_s16le', '-protocol_whitelist', 'pipe',
     '-f', 'hash', '-hash', 'sha256', 'pipe:1']
  end
end
