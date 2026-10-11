class JrcNico::OperationalInference
  def self.call(account:, user:, kind:, message:, context:, history: [])
    payload = { request_id: SecureRandom.uuid, account_id: account.id, kind: kind, message: message, context: context, history: history }
    # Reserve both provider attempts, including prompts, framing and up to 2,000 output tokens each.
    reservation = 2 * (payload.to_json.bytesize + 16_000)
    raise JrcNico::RuntimeClient::Error, 'context_too_large' if reservation > 270_000
    metered(account: account, user: user, kind: kind, reservation_tokens: reservation, request_id: payload[:request_id]) do |provider, ledger|
      JrcNico::RuntimeClient.new(provider: provider, ledger: ledger).operate(payload)
    end
  end

  def self.transcribe(account:, user:, upload:)
    raise ArgumentError unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.between?(16, 4_194_304)

    mime = upload.content_type.to_s.split(';').first
    raise ArgumentError unless %w[audio/webm audio/mp4 audio/ogg audio/wav audio/mpeg].include?(mime)

    audio = upload.read(4_194_305)
    raise ArgumentError if audio.bytesize > 4_194_304

    request_id = SecureRandom.uuid
    metered(account: account, user: user, kind: 'transcription', request_id: request_id) do |provider, ledger|
      JrcNico::RuntimeClient.new(provider: provider, ledger: ledger).transcribe(request_id: request_id, account_id: account.id, mime_type: mime,
                                           audio_base64: Base64.strict_encode64(audio))
    end
  end

  def self.metered(account:, user:, kind:, reservation_tokens: 270_000, request_id: SecureRandom.uuid)
    provider = JrcAi::AccountProvider.resolve(account) if ENV['NICO_MODE'] == 'provider'
    inference = account.with_lock do
      reservation = JrcNico::RunCapacity.reservation_for!(account, reservation_tokens: reservation_tokens)
      record = JrcNico::Inference.create!(account: account, user: user, reserved_tokens: reservation)
      JrcNico::ReservationLedger.new(record).prepare!(kind: kind, provider: provider, request_id: request_id)
      record
    end
    ledger = JrcNico::ReservationLedger.new(inference)
    result = yield(provider, ledger)
    ledger.complete!(result)
    result
  rescue StandardError => error
    JrcNico::ReservationLedger.new(inference).failed!(error) if inference
    raise
  end
end
