class JrcFlowEffects::Apply
  def initialize(account:, user:, access_token:)
    @authority = JrcFlowEffects::Authority.new(account: account, user: user, access_token: access_token)
  end

  def call(display_id, input)
    value = JrcFlowEffects::Request.validate(input)
    raise ArgumentError, 'control_unavailable' unless JrcFlowEffects::ControlRevision.available?

    Conversation.transaction do
      @authority.authorize!(lock: true)
      JrcDomainCommands::Scope.new(@authority).authorize!(input) if input['operation'] == 'domain'
      conversation = @authority.account.conversations.lock.find_by!(display_id: JrcFlowEffects::Request.integer(display_id))
      digest = JrcFlowEffects::Request.digest(input, account_id: @authority.account.id, conversation_id: conversation.display_id)
      replay(conversation, input, digest) || perform(conversation, input, value, digest)
    end
  end

  private

  def replay(conversation, input, digest)
    receipt = JrcFlowEffectReceipt.find_by(account_id: @authority.account.id,
                                           organization_id: input['organization_id'], operation_id: input['operation_id'])
    receipt&.verify!(conversation: conversation, user: @authority.user, proof: input['dispatch_proof'], request_hash: digest)
  end

  def perform(conversation, input, value, digest)
    snapshot = JrcFlowEffects::ControlRevision.snapshot(conversation)
    verify_snapshot!(snapshot, input)
    result = apply_action(conversation, input, value)
    after = JrcFlowEffects::ControlRevision.snapshot(conversation.reload)
    raise ArgumentError, 'destination_changed' unless snapshot.except('control_revision') == after.except('control_revision')

    attributes = input.slice('organization_id', 'operation_id', 'operation', 'resource_id', 'resource_revision')
                      .merge(snapshot.except('control_revision'))
    JrcFlowEffectReceipt.create!(attributes.merge(
                                   conversation: conversation, actor_user_id: @authority.user.id, request_hash: digest,
                                   dispatch_proof_hash: Digest::SHA256.hexdigest(input['dispatch_proof']),
                                   control_revision_before: snapshot['control_revision'], control_revision_after: after['control_revision'],
                                   message_id: input['operation'] == 'domain' ? nil : result&.id,
                                   domain_result: input['operation'] == 'domain' ? result : nil
                                 ))
  end

  def verify_snapshot!(snapshot, input)
    same = snapshot['inbox_id'] == JrcFlowEffects::Request.integer(input['inbox_id']) &&
           snapshot['remote_contact_id'] == JrcFlowEffects::Request.integer(input['remote_contact_id']) &&
           snapshot['control_revision'] == JrcFlowEffects::Request.integer(input['expected_control_revision'], zero: true)
    raise ArgumentError, 'control_changed' unless same
  end

  def apply_action(conversation, input, value)
    case input['operation']
    when 'domain'
      JrcDomainCommands::Apply.new(@authority, conversation, input, value).call
    when 'note'
      apply_note(conversation, input, value)
    when 'resolve'
      raise ArgumentError, 'value' unless value == 'RESOLVED'

      conversation.update!(status: :resolved)
      nil
    else
      apply_resource(conversation, input, value)
      nil
    end
  end

  def apply_note(conversation, input, value)
    raise ArgumentError, 'value' unless value.is_a?(String) && value.present? && value.bytesize.between?(1, 4096)

    metadata = { jrc_flow_effect_id: input['operation_id'], jrc_flow_effect_organization_id: input['organization_id'] }
    Messages::MessageBuilder.new(@authority.user, conversation, content: value, private: true, content_attributes: metadata).perform
  end

  def apply_resource(conversation, input, value)
    definition, metadata = resource(input)
    if input['operation'] == 'tag'
      raise ArgumentError, 'value' unless value.nil?

      conversation.label_list = (conversation.label_list + [definition.title]).uniq
    else
      typed = JrcFlowEffects::Resources.typed_value!(metadata[:definition], value)
      conversation.custom_attributes = conversation.custom_attributes.to_h.merge(definition.attribute_key => typed)
    end
    conversation.save!
  end

  def resource(input)
    scope = if input['operation'] == 'tag'
              @authority.account.labels
            else
              @authority.account.custom_attribute_definitions.where(attribute_model: :conversation_attribute)
            end
    definition = scope.lock.find(JrcFlowEffects::Request.integer(input['resource_id']))
    metadata = JrcFlowEffects::Resources.metadata(definition, input['operation'])
    raise ArgumentError, 'resource_changed' unless metadata && metadata[:revision] == input['resource_revision']

    [definition, metadata]
  end
end
