require 'digest'
require 'stringio'

class JrcBroker::HistorySyncMedia
  MAX_BYTES = 16.megabytes
  KEYS = %w[reference_id media_type filename mime_type byte_size sha256].freeze
  TYPES = { 'IMAGE' => 'image', 'AUDIO' => 'audio', 'VIDEO' => 'video', 'DOCUMENT' => 'file', 'STICKER' => 'image' }.freeze

  def self.valid_descriptor?(value)
    value.is_a?(Hash) && value.keys.sort == KEYS.sort && valid_identity?(value) && valid_bounds?(value)
  end

  def self.valid_identity?(value)
    JrcBroker::HistoryImport::UUID.match?(value['reference_id'].to_s) && TYPES.key?(value['media_type']) &&
      /\A[a-f0-9]{64}\z/.match?(value['sha256'].to_s)
  end

  def self.valid_bounds?(value)
    value['byte_size'].is_a?(Integer) && value['byte_size'].between?(1, MAX_BYTES) &&
      value['filename'].is_a?(String) && value['filename'].bytesize.between?(1, 255) &&
      !%r{[\x00-\x1f/\\]}.match?(value['filename']) && value['mime_type'].is_a?(String) && value['mime_type'].bytesize.between?(1, 255)
  end

  def self.scope(scope, input)
    JrcBrokerHistoryMedia.where(account_id: scope.account.id, inbox_id: scope.inbox.id,
                                organization_id: input.fetch('organization_id'), integration_id: input.fetch('integration_id'),
                                history_account_identity: input.fetch('history_account_identity'))
  end

  def initialize(importer)
    @importer = importer
  end

  # A reserved blob key survives a crash before PUT. Retrying uploads the same
  # validated bytes to that key; no public URL or caller-selected host is used.
  def upload(inbox_id, input, descriptor, uploaded)
    raise ArgumentError, 'historical_media_descriptor' unless self.class.valid_descriptor?(descriptor) && uploaded.respond_to?(:read)

    @importer.with_scope(inbox_id, input) { |_scope| nil }
    bytes = uploaded.read(MAX_BYTES + 1)
    verify_bytes!(bytes, descriptor)
    digest = Digest::SHA256.hexdigest(descriptor.sort.to_h.to_json)
    intent = reserve(inbox_id, input, descriptor, digest, bytes)
    # A repeat can also repair loss of the private object. Its immutable intent
    # admits exactly these bytes; the key is never retargeted or deleted.
    write_object!(intent.blob, bytes, descriptor)
    confirm_upload!(inbox_id, input, intent, digest)
  end

  def self.bind!(scope, input, receipt)
    return unless input.dig('content', 'type') == 'MEDIA'

    descriptor = input.fetch('content').slice(*KEYS)
    intent = self.scope(scope, input).lock.find_by!(reference_id: descriptor.fetch('reference_id'))
    assert_binding!(intent, scope, receipt, descriptor)

    intent.update!(message_id: receipt.message_id, receipt_id: receipt.id, state: 'ATTACH_PENDING') if intent.state == 'STORED'
  end

  def self.assert_binding!(intent, scope, receipt, descriptor)
    valid = intent.descriptor == descriptor && %w[STORED ATTACH_PENDING READY].include?(intent.state) &&
            [nil, receipt.message_id].include?(intent.message_id) && [nil, receipt.id].include?(intent.receipt_id) &&
            intent.instance_id == scope.binding.instance_id && intent.destination_revision == scope.integration.destination_revision
    raise ArgumentError, 'historical_media_conflict' unless valid
  end

  def verify_bytes!(bytes, descriptor)
    mime = Marcel::MimeType.for(StringIO.new(bytes), name: descriptor.fetch('filename'))
    valid = bytes.bytesize == descriptor.fetch('byte_size') && Digest::SHA256.hexdigest(bytes) == descriptor.fetch('sha256') &&
            mime == descriptor.fetch('mime_type') && mime_allowed?(mime, descriptor.fetch('media_type'))
    raise ArgumentError, 'historical_media_integrity' unless valid
  end

  def verify_blob!(blob, descriptor)
    bytes = +''.b
    blob.download do |chunk|
      raise ArgumentError, 'historical_media_integrity' if chunk.bytesize > descriptor.fetch('byte_size') - bytes.bytesize

      bytes << chunk
    end
    verify_bytes!(bytes, descriptor)
  end

  private

  def confirm_upload!(inbox_id, input, intent, digest)
    @importer.with_scope(inbox_id, input) do |scope|
      current = self.class.scope(scope, input).lock.find(intent.id)
      raise ArgumentError, 'historical_media_conflict' unless current.descriptor_hash == digest

      current.update!(state: 'STORED') if current.state == 'RESERVED'
      { protocol: JrcBroker::HistorySyncV2::PROTOCOL, reference_id: current.reference_id,
        state: 'STORED', sha256: current.descriptor.fetch('sha256') }
    end
  end

  def write_object!(blob, bytes, descriptor)
    blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
    verify_blob!(blob, descriptor)
  end

  def mime_allowed?(mime, type)
    return Attachment::ACCEPTABLE_FILE_TYPES.include?(mime) if type == 'DOCUMENT'

    prefix = type == 'STICKER' ? 'image/' : "#{type.downcase}/"
    mime.start_with?(prefix)
  end

  def reserve(inbox_id, input, descriptor, digest, bytes)
    @importer.with_scope(inbox_id, input) do |scope, user, token_id, token_sha256|
      JrcBroker::HistorySyncV2.lock_key(['jrc-history-media', scope.account.id, scope.inbox.id, input.fetch('integration_id'),
                                         input.fetch('history_account_identity'), descriptor.fetch('reference_id')].join(':'))
      prior = self.class.scope(scope, input).lock.find_by(reference_id: descriptor.fetch('reference_id'))
      authority = { user: user, token_id: token_id, token_sha256: token_sha256 }
      if prior
        verify_prior!(prior, scope, authority, digest)
      else
        create_intent!(scope, input, { descriptor: descriptor, digest: digest, bytes: bytes }, authority)
      end
    end
  end

  def verify_prior!(prior, scope, authority, digest)
    valid = prior.descriptor_hash == digest && prior.instance_id == scope.binding.instance_id &&
            prior.destination_revision == scope.integration.destination_revision && prior.user_id == authority.fetch(:user).id &&
            prior.access_token_id == authority.fetch(:token_id) &&
            ActiveSupport::SecurityUtils.secure_compare(prior.access_token_sha256, authority.fetch(:token_sha256))
    raise ArgumentError, 'historical_media_conflict' unless valid

    prior
  end

  def create_intent!(scope, input, file, authority)
    raise ArgumentError, 'historical_media_backpressure' if JrcBrokerHistoryMedia.where(account: scope.account).where.not(state: 'READY').count >= 200

    descriptor = file.fetch(:descriptor)
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: descriptor.fetch('filename'), byte_size: descriptor.fetch('byte_size'),
      checksum: Digest::MD5.base64digest(file.fetch(:bytes)), content_type: descriptor.fetch('mime_type')
    )
    self.class.scope(scope, input).create!(
      user: authority.fetch(:user), blob: blob,
      access_token_id: authority.fetch(:token_id), access_token_sha256: authority.fetch(:token_sha256),
      reference_id: descriptor.fetch('reference_id'), descriptor: descriptor, descriptor_hash: file.fetch(:digest),
      instance_id: input.fetch('instance_id'), destination_revision: input.fetch('destination_revision')
    )
  end
end
