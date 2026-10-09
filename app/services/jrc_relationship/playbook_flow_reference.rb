require 'digest'

# References are explicit native IDs. No CRM/Service Desk unit mapping is inferred.
class JrcRelationship::PlaybookFlowReference
  STEP_FIELDS = %w[kind title after_days step_key flow_id flow_lock_version flow_digest conversation_id contact_id business_unit_id message_id].freeze
  attr_reader :context, :assignment, :step, :source_key, :flow, :conversation, :contact, :configuration, :playbook, :input_message

  def initialize(context:, assignment:, step:, source_key:, playbook: nil)
    @context = JrcRelationship::Context.new(context.member)
    @assignment = @context.assignment(assignment.id, write: true)
    raise ArgumentError, 'Flow step must be a hash' unless step.is_a?(Hash)

    @step = step.deep_stringify_keys
    @source_key = source_key
    validate_input!
    raise Pundit::NotAuthorizedError unless @context.policy.admin? && JrcFlows::Access.enabled?(@context.account)

    bind_unit!
    bind_customer!
    bind_flow!
    bind_message!
    @configuration = @context.configuration(@assignment)
    @playbook = playbook
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(canonical(value).to_json)
  end

  def self.canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def self.definition_digest(flow)
    digest(flow.attributes.slice('id', 'account_id', 'created_by_id', 'connection_id', 'status', 'kind', 'engine',
                                 'graph', 'settings', 'lock_version', 'source_ciphertext', 'credential_ciphertext'))
  end

  def scope
    { 'account_id' => context.account.id, 'account_user_id' => context.member.id, 'assignment_id' => assignment.id,
      'business_unit_id' => assignment.business_unit_id, 'contact_id' => contact.id,
      'conversation_id' => conversation.id, 'inbox_id' => conversation.inbox_id }
  end

  def payload_digest
    value = { 'scope' => scope, 'step' => step, 'source_key' => source_key, 'flow_digest' => step['flow_digest'],
                      'access_signature' => context.access_signature,
                      'assignment' => assignment.attributes.slice('account_id', 'company_id', 'contact_id', 'owner_id', 'team_id',
                                                                  'business_unit_id', 'status', 'settings', 'updated_at'),
                      'contact' => signed_contact,
                      'conversation' => signed_conversation,
                      'configuration' => configuration.attributes.slice('id', 'version', 'scope_key', 'rules'),
                      'playbook' => playbook&.snapshot }
    value['input_message_digest'] = JrcRelationship::PlaybookFlowInput.digest(input_message) if input_message
    self.class.digest(value)
  end

  def normalize_owned_mutations!(baseline)
    @owned_baseline = baseline
    self
  end

  def native_variables
    { 'message' => input_message&.content.to_s.first(10_000), 'contact.name' => contact.name.to_s,
      'contact.email' => contact.email.to_s, 'contact.phone_number' => contact.phone_number.to_s,
      'conversation.id' => conversation.display_id.to_s, 'inbox.name' => conversation.inbox.name }
  end

  def event_key
    "relationship-playbook:#{self.class.digest('account_id' => context.account.id, 'assignment_id' => assignment.id,
                                               'step_key' => step['step_key'], 'source_key' => source_key)}"
  end

  def stamp
    scope.merge('payload_digest' => payload_digest, 'step' => step, 'source_key' => source_key,
                'flow_digest' => step['flow_digest'], 'version' => flow.lock_version)
  end

  def effects_enabled?
    configuration.effective_rules['playbook_flow_effects_enabled'] == true
  end

  def policy
    JrcRelationship::PlaybookFlowPolicy.new(self)
  end

  def published_playbook?
    return false unless published_identity?

    current = JrcRelationship::Playbook.where(account_id: context.account.id).find(playbook.id)
    version = current.versions.find_by(account_id: context.account.id, version: current.version)
    current.snapshot == playbook.snapshot && version&.payload == current.snapshot
  end

  private

  def signed_contact
    attributes = contact.attributes.slice('id', 'account_id', 'company_id', 'name', 'email', 'phone_number')
    @owned_baseline ? attributes.merge(@owned_baseline.fetch('contact').slice('name', 'email', 'phone_number')) : attributes
  end

  def signed_conversation
    attributes = conversation.attributes.slice('id', 'account_id', 'contact_id', 'contact_inbox_id', 'inbox_id',
                                                'assignee_id', 'assignee_agent_bot_id', 'team_id', 'status')
    @owned_baseline ? attributes.merge(@owned_baseline.fetch('conversation').slice('assignee_id', 'assignee_agent_bot_id', 'team_id', 'status')) : attributes
  end

  def bind_message!
    return unless step.key?('message_id')

    @input_message = JrcRelationship::PlaybookFlowInput.find!(account: context.account, conversation: conversation,
                                                            contact_id: contact.id, message_id: step.fetch('message_id'))
  end

  def published_identity?
    playbook&.persisted? && playbook.account_id == context.account.id && playbook.active
  end

  def validate_input!
    valid_source = source_key.is_a?(String) && source_key.bytesize.between?(1, 512) && !source_key.match?(/[\x00-\x1f\x7f]/)
    raise ArgumentError, 'Explicit flow references and bounded source/step keys are required' unless valid_source && valid_step?
  end

  def valid_step?
    valid_key = step['step_key'].is_a?(String) && step['step_key'].match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
    step['kind'] == 'flow' && JrcRelationship::PlaybookSteps.valid?([step]) && (step.keys - STEP_FIELDS).empty? && valid_key
  end

  def bind_unit!
    raise Pundit::NotAuthorizedError unless step['business_unit_id'] == assignment.business_unit_id
    return unless assignment.business_unit_id

    JrcCrm::BusinessUnit.active.where(account_id: context.account.id).find(assignment.business_unit_id)
  end

  def bind_customer!
    customer = assignment.customer_context(context.member)
    @contact = customer.contacts.find(step['contact_id'])
    @conversation = customer.conversations.find(step['conversation_id'])
    raise Pundit::NotAuthorizedError unless conversation.contact_id == contact.id && conversation.account_id == context.account.id

    bind_inbox!
  end

  def bind_inbox!
    identity = conversation.contact_inbox
    raise Pundit::NotAuthorizedError unless identity.contact_id == contact.id && identity.inbox_id == conversation.inbox_id
    raise Pundit::NotAuthorizedError unless context.account.inboxes.exists?(conversation.inbox_id)
    raise Pundit::NotAuthorizedError unless ConversationPolicy.new(context.to_h, conversation).show?
  end

  def bind_flow!
    @flow = JrcFlow.active.where(account_id: context.account.id).find(step['flow_id'])
    raise Pundit::NotAuthorizedError unless context.account.account_users.exists?(user_id: flow.created_by_id, role: 'administrator')

    bind_flow_version!
    raise Pundit::NotAuthorizedError unless Array(flow.settings['inbox_ids']).include?(conversation.inbox_id)
  end

  def bind_flow_version!
    raise ArgumentError, 'Published flow version changed; preview again' unless flow.lock_version == step['flow_lock_version'] &&
                                                                                self.class.definition_digest(flow) == step['flow_digest']
  end
end
