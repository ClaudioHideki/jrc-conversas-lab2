# frozen_string_literal: true

require 'json'

class JrcContactCenter::AudioMediaProbe
  BINARY = '/usr/bin/ffprobe'
  FIELDS = 'format=format_name,duration:stream=codec_name,codec_type,duration,sample_rate,channels'

  def call(file)
    identity = runtime_identity
    decoder = JrcContactCenter::AudioMediaDecoder.new
    decoder_version = decoder.identity
    return failure('unavailable') unless identity && decoder_version

    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: arguments, file: file)
    return failure(result.state == :nonzero ? 'invalid' : 'unavailable') unless result.state == :ok

    metadata = JrcContactCenter::AudioMediaMetadata.extract(JSON.parse(result.output), version: identity)
    return failure('invalid') unless metadata

    state = decoder.call(file)
    return failure(state) unless state == 'valid'

    { state: 'valid', metadata: metadata, decoder_version: decoder_version }
  rescue JSON::ParserError
    failure('invalid')
  end

  private

  def failure(state)
    { state: state, metadata: {}, decoder_version: nil }
  end

  def runtime_identity
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-version'])
    return unless result.state == :ok

    identity = result.output.lines.first.to_s.strip.first(200)
    identity if identity.start_with?('ffprobe version ') && fd_available?
  end

  def fd_available?
    result = JrcContactCenter::AudioProbeProcess.new.call(arguments: [BINARY, '-protocols'])
    result.state == :ok && result.output.split('Output:').first.lines.map(&:strip).include?('fd')
  end

  # Only stdin is the owned seekable file. fd: cannot select another descriptor via its URL.
  def arguments
    [BINARY, '-v', 'quiet', '-max_alloc', '67108864', '-protocol_whitelist', 'fd',
     '-format_whitelist', JrcContactCenter::AudioMediaDecoder::FORMATS, '-max_streams', '1', '-threads', '1',
     '-probesize', '1048576', '-analyzeduration', '2000000', '-i', 'fd:',
     '-show_entries', FIELDS, '-of', 'json']
  end
end
