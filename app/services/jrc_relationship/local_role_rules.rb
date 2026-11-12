# Explicit, versioned local restrictions intersect native module permissions.
# Defaults are editor presets, never grants applied to existing users.
class JrcRelationship::LocalRoleRules
  ACTIONS = %w[view work team manage_portfolios configure request_transfer approve_transfer execute_transfer
               request_eligibility manage_eligibility export_data export_history document_view document_download
               document_upload document_replace document_manage document_restricted].freeze
  SCOPES = %w[authorized own team managed].freeze
  DEFAULTS = {
    'viewer' => { 'scope' => 'authorized', 'actions' => %w[view] },
    'analyst' => { 'scope' => 'own', 'actions' => %w[view work request_transfer document_view document_upload] },
    'supervisor' => { 'scope' => 'team', 'actions' => %w[view work team request_transfer approve_transfer request_eligibility document_view] },
    'manager' => { 'scope' => 'managed', 'actions' => ACTIONS.dup }
  }.freeze
  # The approved profiles have invariant boundaries. Administrators may narrow
  # capabilities or explicitly allow read/export operations; they cannot turn
  # Consulta into an operator or a supervisor into an eligibility executor.
  READ_ACTIONS = %w[view export_data export_history document_view document_download document_restricted].freeze
  ROLE_ACTION_LIMITS = {
    'viewer' => READ_ACTIONS,
    'analyst' => %w[view work request_transfer document_view document_download document_upload document_replace].freeze,
    'supervisor' => %w[view work team request_transfer approve_transfer request_eligibility export_data export_history
                       document_view document_download document_restricted].freeze,
    'manager' => ACTIONS
  }.freeze
  INDEPENDENT = %w[export_data export_history document_view document_download document_upload document_replace document_manage document_restricted].freeze

  def self.normalize!(input)
    raise ArgumentError, 'Local permissions must be a configured object' unless input.is_a?(Hash)
    raise ArgumentError, 'Unknown local role settings' unless input.keys.sort == %w[enabled members roles]
    raise ArgumentError, 'Local permission activation must be explicit' unless [true, false].include?(input['enabled'])
    roles = input['roles']
    raise ArgumentError, 'Configure the four local roles' unless roles.is_a?(Hash) && roles.keys.sort == DEFAULTS.keys.sort
    roles.each do |name, role|
      unless role.is_a?(Hash) && role.keys.sort == %w[actions scope] && SCOPES.include?(role['scope']) && valid_actions?(role['actions']) &&
             (role['actions'] - ROLE_ACTION_LIMITS.fetch(name)).empty?
        raise ArgumentError, 'Invalid role scope or actions'
      end
    end
    members = input['members']
    raise ArgumentError, 'Configure at most 500 explicit user bindings' unless members.is_a?(Array) && members.size <= 500
    ids = []
    members.each do |member|
      unless member.is_a?(Hash) && member.keys.sort == %w[document_categories grants role user_id] &&
             member['user_id'].is_a?(Integer) && member['user_id'].positive? && roles.key?(member['role']) &&
             valid_actions?(member['grants']) && (member['grants'] - INDEPENDENT).empty? &&
             member['document_categories'].is_a?(Array) && member['document_categories'].size <= 50 &&
             member['document_categories'].all? { |value| value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,80}\z/) }
        raise ArgumentError, 'Invalid explicit user grants or document categories'
      end
      ids << member['user_id']
    end
    raise ArgumentError, 'A user must have only one role per scope' unless ids.uniq == ids
    input
  end

  def self.valid_actions?(values)
    values.is_a?(Array) && values.uniq == values && (values - ACTIONS).empty?
  end

  def self.binding(input, user_id)
    normalize!(input).fetch('members').find { |row| row['user_id'] == user_id }
  end

  def self.allowed?(input, user_id:, action:, owner_id: nil, team_id: nil, actor_team_ids: [], document_category: nil)
    return false unless ACTIONS.include?(action)
    return true if input.nil?
    normalize!(input)
    return true unless input['enabled']
    return false unless ACTIONS.include?(action)
    member = binding(input, user_id)
    return false unless member
    role = input.fetch('roles').fetch(member['role'])
    return false unless role['actions'].include?(action)
    return false if INDEPENDENT.include?(action) && !member['grants'].include?(action)
    if action.start_with?('document_') && document_category
      return false unless member['document_categories'].include?(document_category)
    end
    # The explicit :metadata sentinel checks capabilities, never record access.
    return true if owner_id == :metadata
    case role['scope']
    when 'own' then owner_id == user_id
    when 'team' then owner_id == user_id || (team_id && actor_team_ids.include?(team_id))
    else true # Native account/unit/client scopes must already authorize the record.
    end
  end
end
