class JrcCustomers::TaxonomyWriter
  FIELDS = %w[kind name active position description selection_mode criteria modules].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def save!(taxonomy:, attributes:, expected_revision: nil)
    @account.with_lock do
      prepare_change!(taxonomy, expected_revision)
      created = taxonomy.new_record?
      old_name = taxonomy.name
      taxonomy.assign_attributes(attributes.to_h.stringify_keys.slice(*FIELDS))
      preserve_assigned_classification!(taxonomy, old_name) unless created
      taxonomy.save!
      audit!(taxonomy, created ? 'customer_segment_created' : 'customer_segment_updated')
      taxonomy
    end
  end

  def override!(taxonomy:, kind:, id:, mode:)
    @account.with_lock do
      authorize!
      raise ActiveRecord::RecordNotFound unless taxonomy.account_id == @account.id

      subject = subject!(kind, id)
      key = kind == 'companies' ? :company_id : :contact_id
      choice = taxonomy.overrides.find_or_initialize_by({ 'account_id' => @account.id, key.to_s => subject.id })
      choice.update!(mode: mode)
      audit!(taxonomy, 'customer_segment_override_changed')
      choice
    end
  end

  def remove_override!(taxonomy:, id:)
    @account.with_lock do
      authorize!
      choice = JrcCustomers::SegmentMembers.new(account: @account, actor: @actor, taxonomy: taxonomy).overrides.find(id)
      choice.destroy!
      audit!(taxonomy, 'customer_segment_override_changed')
    end
  end

  def destroy!(taxonomy:)
    @account.with_lock do
      authorize!
      raise ActiveRecord::RecordNotFound unless taxonomy.account_id == @account.id

      taxonomy.reload
      if taxonomy.overrides.exists? || taxonomy.modules.any? || @account.master_companies.exists?(segment: taxonomy.name)
        taxonomy.errors.add(:base, 'Segment has dependencies; remove its manual choices, module uses and company classifications before deleting')
        raise ActiveRecord::RecordInvalid, taxonomy
      end
      audit!(taxonomy, 'customer_segment_deleted')
      taxonomy.destroy!
    end
  end

  private

  def preserve_assigned_classification!(taxonomy, old_name)
    return unless @account.master_companies.exists?(segment: old_name)

    taxonomy.errors.clear
    if old_name != taxonomy.name
      taxonomy.errors.add(:name, 'cannot rename a classification assigned to companies; preserve their existing classification')
    end
    if taxonomy.selection_mode_in_database == 'classification' && taxonomy.selection_mode != 'classification'
      taxonomy.errors.add(:selection_mode, 'is assigned to companies; create a separate dynamic segment to preserve their classification')
    end
    raise ActiveRecord::RecordInvalid, taxonomy if taxonomy.errors.any?
  end

  def prepare_change!(taxonomy, expected_revision)
    authorize!
    raise ActiveRecord::RecordNotFound unless taxonomy.account_id == @account.id

    taxonomy.reload if taxonomy.persisted?
    return unless expected_revision && taxonomy.updated_at&.iso8601(6) != expected_revision

    raise JrcCustomers::CompanyWriter::StaleRevision, 'Segment changed; reload before saving'
  end

  def authorize!
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    member = AccountUser.find_by!(account_id: @account.id, user_id: @actor.id)
    context = { account: @account, user: @actor, account_user: member }
    raise Pundit::NotAuthorizedError unless JrcCustomers::DirectoryPolicy.new(context, :directory).administer?
  end

  def subject!(kind, id)
    return JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).find(id) if kind == 'contacts'
    raise ActionController::BadRequest, 'Invalid subject kind' unless kind == 'companies'

    JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies).find(id)
  end

  def audit!(taxonomy, event)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: taxonomy, event_type: event,
                                metadata: { name: taxonomy.name, selection_mode: taxonomy.selection_mode, active: taxonomy.active })
  end
end
