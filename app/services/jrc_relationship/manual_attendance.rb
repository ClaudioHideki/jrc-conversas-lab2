require 'digest'

class JrcRelationship::ManualAttendance
  TYPES = %w[meeting demonstration visit].freeze

  def initialize(context)
    @context = context
  end

  def call(assignment:, attributes:)
    @context.assignment(assignment.id, write: true)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    attrs = attributes.to_h.with_indifferent_access
    validate_request!(attrs)
    participants = authorized_participants(assignment, attrs)
    payload = normalized_payload(attrs, participants[:contact], participants[:deal])
    digest = Digest::SHA256.hexdigest(payload.to_json)
    key = "manual-attendance:#{assignment.id}:#{attrs[:request_id]}"
    assignment.with_lock { persist_attendance!(assignment, participants, payload, key, digest) }
  end

  def self.eligible?(activity)
    TYPES.include?(activity.activity_type) && activity.metadata['relationship_manual_attendance'] == true &&
      activity.contact_id.present? && activity.conversation_id.nil? && activity.metadata['relationship_resource_type'].blank?
  end

  private

  def persist_attendance!(assignment, participants, payload, key, digest)
    existing = @context.account.jrc_crm_activities.where("metadata ->> 'relationship_attendance_key' = ?", key).first
    if existing
      JrcRelationship::SurveySource.new(existing, @context)
      validate_replay!(existing, digest)
      return existing
    end

    create_attendance!(assignment, participants, payload, attendance_metadata(assignment, key, digest, payload))
  end

  def validate_replay!(activity, digest)
    return if activity.metadata['relationship_attendance_digest'] == digest

    raise ArgumentError, 'Attendance request was reused with a different payload'
  end

  def validate_request!(attrs)
    raise ArgumentError, 'Invalid attendance type' unless TYPES.include?(attrs[:activity_type])
    raise ArgumentError, 'Invalid attendance request' unless attrs[:request_id].to_s.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
    raise ArgumentError, 'Completion must be boolean' unless [true, false].include?(attrs[:completed])
  end

  def authorized_participants(assignment, attrs)
    customer = assignment.customer_context(@context.member)
    contact = customer.contacts.find(attrs.fetch(:contact_id))
    JrcOperations::Access.contact!(@context.member, contact.id)
    deal = customer.deals.find(attrs.fetch(:deal_id))
    raise Pundit::NotAuthorizedError unless deal_matches_contact?(deal, contact)

    { contact: contact, deal: deal }
  end

  def deal_matches_contact?(deal, contact)
    deal.contact_id == contact.id || deal.deal_contacts.exists?(contact_id: contact.id) ||
      (contact.company_id.present? && deal.company_id == contact.company_id)
  end

  def attendance_metadata(assignment, key, digest, payload)
    metadata = { relationship_attendance_key: key, relationship_attendance_digest: digest,
                 relationship_attendance_assignment_id: assignment.id, relationship_manual_attendance: true }
    %w[contract product].each { |kind| metadata["relationship_#{kind}_id"] = payload["#{kind}_id"] if payload["#{kind}_id"] }
    metadata
  end

  def create_attendance!(assignment, participants, payload, metadata)
    activity = JrcCrm::Activity.create!(activity_attributes(assignment, participants, payload).merge(metadata: metadata))
    origin = JrcRelationship::SurveySource.new(activity, @context)
    origin.contract
    origin.product
    @context.audit!(activity, after: { attendance_type: activity.activity_type, completed: activity.status == 'completed' },
                              action: 'manual_attendance_recorded')
    activity
  end

  def activity_attributes(assignment, participants, payload)
    { account: @context.account, user: @context.user, company: participants[:contact].master_company,
      contact: participants[:contact], deal: participants[:deal], business_unit: assignment.business_unit,
      activity_type: payload['activity_type'], title: payload['title'], description: payload['description'], due_at: payload['due_at'],
      status: payload['completed'] ? 'completed' : 'scheduled', completed_at: payload['completed'] ? Time.current : nil }
  end

  def normalized_payload(attrs, contact, deal)
    title = attrs.fetch(:title).to_s.strip
    description = attrs[:description].to_s
    raise ArgumentError, 'Attendance text must be bounded' unless title.length.between?(1, 250) && description.length <= 4000

    payload = { 'title' => title, 'description' => description, 'activity_type' => attrs[:activity_type], 'completed' => attrs[:completed],
                'contact_id' => contact.id, 'deal_id' => deal.id, 'due_at' => attendance_deadline(attrs)&.iso8601(6) }
    payload.merge(commercial_references(attrs))
  end

  def attendance_deadline(attrs)
    due_at = attrs[:due_at].present? ? Time.zone.parse(attrs[:due_at]) : nil
    raise ArgumentError, 'Invalid attendance deadline' if attrs[:due_at].present? && !due_at

    due_at
  end

  def commercial_references(attrs)
    payload = {}
    %w[contract product].each do |kind|
      id = attrs["#{kind}_id"]
      raise ArgumentError, 'Commercial reference must be an explicit ID' if id.present? && !id.to_s.match?(/\A[1-9]\d*\z/)

      payload["#{kind}_id"] = id.present? ? id.to_i : nil
    end
    payload
  end
end
