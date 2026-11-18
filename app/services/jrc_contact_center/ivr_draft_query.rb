# frozen_string_literal: true

class JrcContactCenter::IvrDraftQuery
  attr_reader :page, :per_page

  def initialize(scope:, params:)
    @scope = scope
    @params = params
    validate_filters!
    @page = @params.fetch(:page, 1).to_i.clamp(1, 1_000_000)
    @per_page = @params.fetch(:per_page, 20).to_i.clamp(1, 100)
  end

  def call
    relation = filtered
    total = relation.count
    rows = relation.select('jrc_contact_center_ivr_drafts.*, latest.name AS draft_name, latest.status AS draft_status,
                            latest.revision AS draft_revision, latest.created_at AS draft_updated_at')
                   .order(Arel.sql('latest.created_at DESC, jrc_contact_center_ivr_drafts.id DESC'))
                   .offset((page - 1) * per_page).limit(per_page)
    { rows: rows, meta: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil } }
  end

  private

  def validate_filters!
    valid = %i[q status unit_id].all? { |key| @params[key].nil? || @params[key].is_a?(String) }
    raise JrcContactCenter::OperationError, 'invalid_ivr_filter' unless valid

    validate_status!
    validate_unit!
    validate_pages!
  end

  def validate_status!
    status = @params[:status]
    return if status.nil? || status == '' || %w[draft archived].include?(status)

    raise JrcContactCenter::OperationError, 'invalid_ivr_filter'
  end

  def validate_unit!
    value = @params[:unit_id]
    return if value.nil? || value == ''
    return if value.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i.bit_length <= 63

    raise JrcContactCenter::OperationError, 'invalid_ivr_filter'
  end

  def validate_pages!
    valid = %i[page per_page].all? do |key|
      value = @params[key]
      value.nil? || ((value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[0-9]+\z/))
    end
    raise JrcContactCenter::OperationError, 'invalid_ivr_filter' unless valid
  end

  def filtered
    relation = @scope.relation.joins(<<~SQL.squish)
      INNER JOIN LATERAL (SELECT name, status, revision, created_at FROM jrc_contact_center_ivr_draft_versions
        WHERE ivr_draft_id = jrc_contact_center_ivr_drafts.id AND account_id = jrc_contact_center_ivr_drafts.account_id
        ORDER BY revision DESC LIMIT 1) latest ON TRUE
    SQL
    relation = relation.where(unit_id: @params[:unit_id]) if @params[:unit_id].present?
    relation = relation.where(latest: { status: @params[:status] }) if @params[:status].present?
    query = @params[:q].to_s.strip.first(100)
    relation = relation.where('latest.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    relation
  end
end
