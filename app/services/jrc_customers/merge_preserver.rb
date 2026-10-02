# Runs inside ContactMergeAction's transaction, after locking both native Contacts.
# Does not implement a second merge engine or touch provider/source identifiers.
class JrcCustomers::MergePreserver
  class Conflict < StandardError; end
  ACCOUNT_TABLES = %w[jrc_crm_leads jrc_crm_deals jrc_crm_activities sales_opportunities sales_activities
                      calls csat_survey_responses jrc_nico_erp_bindings jrc_crm_sales_orders jrc_crm_contracts
                      jrc_crm_invoices jrc_crm_backoffice_requests jrc_projects_projects].freeze

  def self.conflict?(account:, base:, source:)
    return true unless [base.account_id, source.account_id].all? { |id| id == account.id }
    return true if [base.company_id, source.company_id].compact.uniq.size > 1
    return true if [base.identifier, source.identifier].compact_blank.uniq.size > 1

    JrcNico::ErpBinding.where(account_id: account.id, contact_id: [base.id, source.id]).count > 1
  end

  def initialize(account:, base:, source:, actor: nil)
    @account, @base, @source, @actor = account, base, source, actor
  end

  def call
    if self.class.conflict?(account: @account, base: @base, source: @source)
      raise Conflict, 'Conflicting company, external identifier or ERP bindings. Reconcile explicitly before merging.'
    end
    assert_reference_tenants!
    snapshot = @source.attributes.except('updated_at').merge('labels' => @source.label_list,
                                                            'avatar_blob_id' => @source.avatar&.blob&.id)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @base, event_type: 'customer_contact_merged',
                               metadata: { source_contact_id: @source.id, source_snapshot: snapshot,
                                           base_snapshot: @base.attributes.except('updated_at') })
    move_account_references
    move_ticket_requesters
    move_deal_contacts
    move_recipients
    move_contact_points
    preserve_identity_points
    preserve_avatars
    preserve_labels
    # Keep the old source ID in each existing audit's metadata before re-parenting its timeline.
    JrcCrm::AuditEvent.where(account_id: @account.id, resource_type: 'Contact', resource_id: @source.id).find_each do |event|
      event.update_columns(resource_id: @base.id, metadata: (event.metadata || {}).merge('original_contact_id' => @source.id))
    end
    @base.assign_attributes(company_id: @base.company_id || @source.company_id,
                            job_title: @base.job_title.presence || @source.job_title,
                            department: @base.department.presence || @source.department,
                            registration_status: [@base.registration_status, @source.registration_status].include?('registered') ? 'registered' : 'provisional')
    @base.save! if @base.changed?
  end

  # Native merge methods use update (not update!). Refuse source deletion if a
  # validation prevented any of those reassignments; the whole transaction rolls back.
  def assert_native_references_moved!
    remaining = Conversation.where(contact_id: @source.id).exists? ||
                Message.where(sender: @source).exists? ||
                ContactInbox.where(contact_id: @source.id).exists? ||
                Note.where(contact_id: @source.id).exists?
    raise Conflict, 'A native reference could not be moved; merge rolled back without deleting the source' if remaining
  end

  private

  def assert_reference_tenants!
    connection = ActiveRecord::Base.connection
    ACCOUNT_TABLES.each do |table|
      invalid = connection.select_value("SELECT 1 FROM #{table} WHERE contact_id = #{@source.id.to_i} AND account_id <> #{@account.id.to_i} LIMIT 1")
      raise Conflict, "Existing cross-account reference in #{table}; repair before merge" if invalid
    end
    if JrcServiceDesk::Ticket.where(requester_id: @source.id).where.not(account_id: @account.id).exists?
      raise Conflict, 'Existing cross-account ticket requester; repair before merge'
    end
    # company_id on a historical ticket/project is retained, never replaced by the
    # current contact company. Disagreement between the two Contacts still blocks.
    invalid_deal = JrcCrm::DealContact.joins(:deal).where(contact_id: @source.id).where.not(jrc_crm_deals: { account_id: @account.id }).exists?
    invalid_recipient = JrcCampaigns::Recipient.joins(:campaign).where(contact_id: @source.id).where.not(jrc_campaigns: { account_id: @account.id }).exists?
    invalid_inbox = ContactInbox.joins(:inbox).where(contact_id: @source.id).where.not(inboxes: { account_id: @account.id }).exists?
    invalid_conversation = Conversation.where(contact_id: @source.id).where.not(account_id: @account.id).exists?
    invalid_message = Message.where(sender: @source).where.not(account_id: @account.id).exists?
    invalid_note = Note.where(contact_id: @source.id).where.not(account_id: @account.id).exists?
    raise Conflict, 'Existing cross-account reference; repair before merge' if [invalid_deal, invalid_recipient, invalid_inbox, invalid_conversation, invalid_message, invalid_note].any?
  end

  def move_account_references
    connection = ActiveRecord::Base.connection
    ACCOUNT_TABLES.each do |table|
      version = table == 'jrc_projects_projects' ? ', lock_version = lock_version + 1' : ''
      connection.execute("UPDATE #{table} SET contact_id = #{@base.id.to_i}#{version} WHERE account_id = #{@account.id.to_i} AND contact_id = #{@source.id.to_i}")
    end
  end

  def move_ticket_requesters
    scope = JrcServiceDesk::Ticket.where(account_id: @account.id, requester_id: @source.id)
    ids = scope.order(:id).pluck(:id)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @base, event_type: 'customer_contact_merged',
                               metadata: { source_contact_id: @source.id, ticket_ids: ids }) if ids.any?
    # Keep historical request_fingerprint, SLA, operator/unit and append-only events.
    scope.update_all(['requester_id = ?, lock_version = lock_version + 1', @base.id])
  end

  def move_deal_contacts
    JrcCrm::DealContact.joins(:deal).where(contact_id: @source.id, jrc_crm_deals: { account_id: @account.id }).find_each do |link|
      if JrcCrm::DealContact.exists?(deal_id: link.deal_id, contact_id: @base.id)
        JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @base, event_type: 'customer_contact_merged',
                                   metadata: { coalesced_deal_contact: link.attributes })
        link.destroy!
      else
        link.update!(contact_id: @base.id)
      end
    end
  end

  def move_recipients
    # Phone numbers, execution IDs, delivery statuses and provider receipts are historical snapshots.
    JrcCampaigns::Recipient.where(contact_id: @source.id, campaign_id: @account.jrc_campaigns.select(:id)).update_all(contact_id: @base.id)
  end

  def move_contact_points
    @source.contact_points.where(account_id: @account.id).find_each do |point|
      duplicate = @base.contact_points.find_by(kind: point.kind, normalized_value: point.normalized_value)
      if duplicate
        JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @base, event_type: 'customer_contact_merged',
                                   metadata: { coalesced_contact_point: point.attributes })
        point.destroy!
      else
        point.update!(contact_id: @base.id)
      end
    end
  end

  def preserve_identity_points
    { 'email' => @source.email, 'phone' => @source.phone_number }.each do |kind, value|
      normalized = JrcCustomers::Identity.point(kind, value)
      next if normalized.nil?
      next if @base.contact_points.exists?(kind: kind, normalized_value: normalized)

      @base.contact_points.create!(account_id: @account.id, kind: kind, value: value, label: "Merged contact ##{@source.id}")
    end
  end

  def preserve_avatars
    blobs = @source.merged_avatars.blobs.to_a
    blobs << @source.avatar.blob if @source.avatar.attached?
    blobs.uniq(&:id).each do |blob|
      next if @base.merged_avatars.blobs.exists?(id: blob.id)
      next if @base.avatar.attached? && @base.avatar.blob.id == blob.id

      @base.merged_avatars.attach(blob)
    end
  end

  def preserve_labels
    @base.label_list.add(*@source.label_list)
    @base.save! if @base.changed? || @source.label_list.any?
  end
end
