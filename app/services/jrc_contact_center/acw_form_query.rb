# frozen_string_literal: true

class JrcContactCenter::AcwFormQuery
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
    rows = relation.select('jrc_contact_center_acw_form_templates.*, latest.name AS form_name, latest.description AS form_description,
                            latest.status AS form_status, latest.revision AS form_revision, latest.created_at AS form_updated_at')
                   .order(Arel.sql('latest.created_at DESC, jrc_contact_center_acw_form_templates.id DESC'))
                   .offset((@page - 1) * @per_page).limit(@per_page)
    { rows: rows, meta: { page: @page, per_page: @per_page, total: total, pages: (total.to_f / @per_page).ceil } }
  end

  private

  def validate_filters!
    valid = %i[q status].all? { |key| @params[key].nil? || @params[key].is_a?(String) }
    valid &&= [nil, '', 'active', 'archived'].include?(@params[:status])
    raise JrcContactCenter::OperationError, 'invalid_acw_form_filter' unless valid

    pages = %i[page per_page].all? do |key|
      value = @params[key]
      value.nil? || ((value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[0-9]+\z/))
    end
    raise JrcContactCenter::OperationError, 'invalid_acw_form_filter' unless pages
  end

  def filtered
    relation = @scope.relation.joins(<<~SQL.squish)
      INNER JOIN LATERAL (SELECT name, description, status, revision, created_at FROM jrc_contact_center_acw_form_versions
        WHERE acw_form_template_id = jrc_contact_center_acw_form_templates.id
          AND account_id = jrc_contact_center_acw_form_templates.account_id
        ORDER BY revision DESC LIMIT 1) latest ON TRUE
    SQL
    relation = relation.where(latest: { status: @params[:status] }) if @params[:status].present?
    query = @params[:q].to_s.strip.first(100)
    relation = relation.where('latest.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    relation
  end
end
