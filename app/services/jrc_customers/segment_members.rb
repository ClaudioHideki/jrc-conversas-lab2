# Membership is evaluated live; it never grants access to a company, contact or
# module. Manual choices survive criteria changes and are scoped again on reads.
class JrcCustomers::SegmentMembers
  SUBJECTS = %w[companies contacts].freeze
  MODES = %w[include exclude].freeze
  def initialize(account:, actor:, taxonomy:, manual_choices: [])
    @account = account
    @actor = actor
    @taxonomy = taxonomy
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
    @directory.authorize!
    raise ActiveRecord::RecordNotFound unless taxonomy.account_id == account.id
    raise ActiveRecord::RecordInvalid, taxonomy unless taxonomy.valid?

    @manual_choices = self.class.resolve_choices(account: account, actor: actor, choices: manual_choices)
  end

  def self.resolve_choices(account:, actor:, choices:)
    raise ActionController::BadRequest, 'At most 100 manual choices per proposal' unless choices.is_a?(Array) && choices.size <= 100

    contacts = JrcCustomers::ContactDirectory.new(account: account, actor: actor).scope
    companies = JrcCrm::CorporateCoverage.new(account: account, user: actor).companies(account.master_companies)
    choices.map do |value|
      choice = value.to_h.stringify_keys
      kind, mode = choice.values_at('subject_kind', 'mode')
      raise ActionController::BadRequest, 'Invalid manual choice' unless SUBJECTS.include?(kind) && MODES.include?(mode)

      subject = (kind == 'companies' ? companies : contacts).find(choice['subject_id'])
      { 'subject_kind' => kind, 'subject_id' => subject.id, 'mode' => mode }
    end
  end

  def companies
    scope = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
    selected = if @taxonomy.selection_mode == 'classification'
                 scope.where(segment: @taxonomy.name)
               else
                 JrcCustomers::SegmentCriteria.new(account: @account, scope: scope).call(@taxonomy.criteria)
               end
    apply_overrides(scope, selected, :company_id)
  end

  def contacts
    scope = @directory.scope
    selected = scope.where(company_id: companies.select(:id))
    apply_overrides(scope, selected, :contact_id)
  end

  def overrides
    scope = @taxonomy.overrides.where(account_id: @account.id)
    company_ids = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies).select(:id)
    scope.where(company_id: company_ids).or(scope.where(contact_id: @directory.scope.select(:id)))
  end

  private

  def apply_overrides(scope, selected, key)
    selected = stored_choices(scope, selected, key) if @taxonomy.persisted?
    kind = key == :company_id ? 'companies' : 'contacts'
    choices = @manual_choices.select { |choice| choice['subject_kind'] == kind }
    included = choices.select { |choice| choice['mode'] == 'include' }.pluck('subject_id')
    excluded = choices.select { |choice| choice['mode'] == 'exclude' }.pluck('subject_id')
    selected.or(scope.where(id: included)).where.not(id: excluded)
  end

  def stored_choices(scope, selected, key)
    choices = @taxonomy.overrides.where(account_id: @account.id).where.not(key => nil)
    selected.or(scope.where(id: choices.where(mode: 'include').select(key)))
            .where.not(id: choices.where(mode: 'exclude').select(key))
  end
end
