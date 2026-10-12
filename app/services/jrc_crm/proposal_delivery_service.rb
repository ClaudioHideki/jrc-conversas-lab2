require 'cgi'
require 'stringio'

module JrcCrm
  class ProposalDeliveryService
    CHANNELS = %w[auto whatsapp email].freeze

    def initialize(proposal:, actor:, channel: 'auto', base_url: nil, idempotency_key: nil)
      @proposal = proposal
      @actor = actor
      @channel = channel.to_s.presence || 'auto'
      @base_url = base_url.to_s.sub(%r{/$}, '')
      @idempotency_key = idempotency_key
    end

    def call
      @proposal.with_lock { deliver_under_lock }
    end

    private

    def deliver_under_lock
      raise ArgumentError, 'Canal de envio inválido' unless CHANNELS.include?(@channel)
      raise ArgumentError, 'Proposta expirada ou encerrada; crie uma nova versão.' if %w[expired canceled accepted rejected].include?(@proposal.public_availability[:state])
      approvals = [@proposal.approval_status, @proposal.commercial_approval_status,
                   @proposal.financial_approval_status, @proposal.technical_approval_status]
      raise ArgumentError, 'Conclua as aprovações internas antes do envio.' unless approvals.all? { |state| %w[approved not_required].include?(state) }
      if JrcCrm::ProposalApprovalRequirements.new(@proposal).required? && @proposal.approval_status != 'approved'
        raise ArgumentError, 'Os descontos ou requisitos técnicos exigem aprovação interna antes do envio.'
      end

      gate = JrcApprovals::CommercialGate.check!(resource: @proposal, user: @actor, key: 'crm.proposal_send')
      if gate[:mode] == 'enforcement' && @idempotency_key.blank?
        raise JrcApprovals::Error, 'IDEMPOTENCY_KEY_REQUIRED'
      end
      if @idempotency_key
        JrcApprovals::Ledger.key!(@idempotency_key)
        document = @proposal.attributes.except('updated_at', 'lock_version', 'status', 'sent_at',
          'last_sent_channel', 'last_sent_message_id', 'last_sent_conversation_id', 'viewed_at', 'last_viewed_at', 'viewed_count')
          .transform_values do |value|
            case value
            when Time, ActiveSupport::TimeWithZone then value.getutc.iso8601(6)
            when DateTime then value.new_offset(0).iso8601(6)
            else value
            end
          end
        @delivery_digest = JrcApprovals::Ledger.digest({ 'terms' => @proposal.financial_items,
          'document' => document,
          'channel' => @channel, 'actor_id' => @actor&.id, 'base_url' => @base_url }.as_json)
        previous = @proposal.events.where(event_type: 'sent').where("metadata ->> 'delivery_key' = ?", @idempotency_key).first
        if previous
          raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless previous.metadata['delivery_digest'] == @delivery_digest

          conversation = @proposal.account.conversations.find(previous.metadata.fetch('conversation_id'))
          return { proposal: @proposal.reload, message: conversation.messages.find(previous.metadata.fetch('message_id')),
                   conversation: conversation }
        end
      end

      conversation = resolve_conversation
      raise StandardError, channel_error_message unless conversation

      # Preserve the schedule actually printed, even after subsequent resends.
      # Use existing event metadata rather than a parallel proposal table.
      anchor_on = Date.iso8601(@proposal.financial_summary[:first_due_date]) - @proposal.first_billing_days.to_i
      pdf_bytes = JrcCrm::ProposalPdfService.new(@proposal).call
      message = build_message(conversation, pdf_bytes)

      status = @proposal.status.in?(%w[accepted rejected canceled]) ? @proposal.status : 'sent'
      @proposal.update!(
        status: status,
        sent_at: Time.current,
        last_sent_channel: channel_key(conversation),
        last_sent_message_id: message.id,
        last_sent_conversation_id: conversation.id
      )
      @proposal.events.create!(
        account_id: @proposal.account_id,
        event_type: 'sent',
        user_id: @actor&.id,
        description: "Proposta enviada por #{channel_label(conversation)} na conversa ##{conversation.display_id}",
        metadata: {
          financial_anchor_on: anchor_on.iso8601,
          channel: channel_key(conversation),
          conversation_id: conversation.id,
          message_id: message.id,
          inbox_id: conversation.inbox_id,
          public_url: public_url,
          delivery_key: @idempotency_key, delivery_digest: @delivery_digest
        }
      )

      { proposal: @proposal.reload, message: message, conversation: conversation }
    end

    private

    def resolve_conversation
      linked = @proposal.deal ? @proposal.deal.conversations.includes(:inbox).order(updated_at: :desc).to_a : []
      return linked.first if @channel == 'auto' && linked.any?

      requested = @channel == 'auto' ? nil : @channel
      matched_linked = linked.find { |conversation| channel_key(conversation) == requested }
      return matched_linked if matched_linked

      contact = @proposal.customer_contact
      return nil unless contact

      candidates = contact.conversations.includes(:inbox).order(updated_at: :desc).to_a
      return candidates.first if requested.nil?

      candidates.find { |conversation| channel_key(conversation) == requested }
    end

    def build_message(conversation, pdf_bytes)
      # Message attachments upload after commit, outside the proposal row lock.
      # Persist the bytes first so that no deferred upload relies on a deleted tempfile.
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(pdf_bytes),
        filename: pdf_filename,
        content_type: 'application/pdf'
      )

      params = {
        content: message_text,
        message_type: 'outgoing',
        attachments: [blob.signed_id],
        content_attributes: {
          jrc_crm_proposal_id: @proposal.id,
          jrc_crm_public_url: public_url
        }
      }
      if channel_key(conversation) == 'email'
        email = @proposal.customer_contact&.email
        raise StandardError, 'O cliente não possui e-mail cadastrado.' if email.blank?

        params[:to_emails] = email
      end

      Messages::MessageBuilder.new(@actor, conversation, params).perform
    end

    def message_text
      name = @proposal.customer_contact&.name.presence || 'cliente'
      <<~TEXT.strip
        Olá #{name}, segue sua proposta comercial JRC:

        #{public_url}

        O PDF da proposta está anexado a esta mensagem.
      TEXT
    end

    def public_url
      "#{@base_url}/jrc/propostas/#{@proposal.account_id}/#{CGI.escape(@proposal.public_token)}"
    end

    def pdf_filename
      safe = @proposal.title.to_s.parameterize.presence || "proposta-#{@proposal.id}"
      "#{safe}.pdf"
    end

    def channel_key(conversation)
      channel = conversation.inbox&.channel_type.to_s
      return 'whatsapp' if channel.match?(/Whatsapp|WhatsApp/i) || conversation.inbox&.name.to_s.match?(/whatsapp/i)
      return 'email' if channel.match?(/Email/i) || conversation.inbox&.inbox_type.to_s.match?(/Email/i)

      'other'
    end

    def channel_label(conversation)
      case channel_key(conversation)
      when 'whatsapp' then 'WhatsApp'
      when 'email' then 'E-mail'
      else conversation.inbox&.name.presence || 'canal vinculado'
      end
    end

    def channel_error_message
      case @channel
      when 'whatsapp'
        'Não foi encontrada uma conversa WhatsApp existente para este cliente.'
      when 'email'
        'Não foi encontrada uma conversa de e-mail existente para este cliente.'
      else
        'O negócio não possui conversa vinculada ao cliente.'
      end
    end
  end
end
