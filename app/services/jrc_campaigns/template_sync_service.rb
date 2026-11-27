class JrcCampaigns::TemplateSyncService
  SETTINGS_KEY = 'jrc_template_settings'.freeze

  class Error < StandardError; end
  class Busy < Error; end

  def initialize(channel)
    @channel = channel
  end

  def call
    claim_sync!
    # Fetch all pages BEFORE replacing the cache. A failed page must not expose
    # a partial catalog or leave a removed template approved locally forever.
    templates = @channel.provider_service.load_templates!
    raise Error, 'Resposta inválida do provedor.' unless templates.is_a?(Array) && templates.all? { |item| item.is_a?(Hash) && item['name'].present? }

    persist_sync(templates: templates)
    @channel.inbox&.update_account_cache
    templates
  rescue Busy
    raise
  rescue StandardError => e
    persist_sync(error: 'Não foi possível sincronizar. Verifique as credenciais e a disponibilidade do provedor.')
    # Do not log token-bearing URLs or provider credentials.
    Rails.logger.warn("[WHATSAPP_TEMPLATE_SYNC] account_id=#{@channel.account_id} channel_id=#{@channel.id} error_class=#{e.class}")
    raise Error, 'Não foi possível sincronizar os modelos. O catálogo anterior foi preservado; verifique a conexão da caixa.'
  end

  private

  def claim_sync!
    @channel.with_lock do
      config = @channel.provider_config.to_h.deep_dup
      settings = config[SETTINGS_KEY] ||= {}
      if settings['sync_started_at'].present? && Time.iso8601(settings['sync_started_at']) > 45.minutes.ago
        raise Busy, 'Já existe uma sincronização em andamento nesta caixa.'
      end

      @sync_id = SecureRandom.uuid
      settings.merge!('sync_id' => @sync_id, 'sync_started_at' => Time.current.utc.iso8601, 'last_attempt_at' => Time.current.utc.iso8601)
      @channel.update_columns(provider_config: config)
    end
  end

  def persist_sync(templates: nil, error: nil)
    @channel.with_lock do
      config = (@channel.provider_config || {}).deep_dup
      settings = config[SETTINGS_KEY] ||= {}
      return if settings['sync_id'] != @sync_id

      settings.delete('sync_id')
      settings.delete('sync_started_at')
      settings['last_attempt_at'] = Time.current.utc.iso8601
      settings['last_error'] = error
      columns = { provider_config: config, updated_at: Time.current }
      unless error
        settings['last_success_at'] = Time.current.iso8601
        columns.merge!(message_templates: templates, message_templates_last_updated: Time.current)
      end
      @channel.update_columns(columns)
    end
  end
end
