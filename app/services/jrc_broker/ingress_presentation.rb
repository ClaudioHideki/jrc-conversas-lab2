class JrcBroker::IngressPresentation
  OBSERVED = '[Saída observada no WhatsApp]'.freeze

  def self.content(input, recipient, origin)
    media = input.dig('content', 'type') == 'MEDIA'
    raw = input.dig('content', media ? 'caption' : 'text')
    group = recipient['kind'] == 'GROUP'
    text = attachment_text(raw, media, group)
    return observed(text, group) if origin == 'EXTERNAL_OBSERVED'
    return text unless group && input['direction'] == 'incoming'

    participant = input.fetch('participant_jid').sub(/:\d+(?=@)/, '')
    "[Participante: #{participant}]\n#{text}"
  end

  def self.attachment_text(raw, media, group)
    media && group && raw.empty? ? '[Anexo]' : raw
  end

  def self.observed(text, group)
    "#{OBSERVED}#{!group && text.empty? ? '' : "\n#{text}"}"
  end
end
