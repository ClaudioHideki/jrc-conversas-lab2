# frozen_string_literal: true

class JrcCulture::Report
  class Invalid < StandardError; end

  TIMEZONE = 'America/Sao_Paulo'
  PER_PAGE = 30
  EXPORT_LIMIT = 2_000

  def initialize(access, filters)
    @access = access
    @filters = filters
  end

  def page
    rows = filtered
    page = @filters[:page].to_i.clamp(1, 10_000)
    {
      summary: summary(base),
      rows: with_details(rows).offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |row| present(row) },
      recent: with_details(base.confirmed).limit(5).map { |row| present(row) },
      page: page, pages: [(rows.count.to_f / PER_PAGE).ceil, 1].max
    }
  end

  def export_rows
    rows = with_details(filtered).limit(EXPORT_LIMIT + 1).to_a
    raise Invalid if rows.size > EXPORT_LIMIT

    rows.map { |row| present(row) }
  end

  private

  def base
    versions = @access.admin_versions
    versions = @filters[:version_id].present? ? versions.where(id: @filters[:version_id]) : versions.published
    grants = JrcCulture::Grant.where(account: @access.account, role: 'employee', unit_id: @access.admin_units.select(:id))
    grants = grants.where(unit_id: @filters[:unit_id]) if @filters[:unit_id].present?
    if @filters[:company_id].present?
      grants = grants.where(unit_id: @access.admin_units.where(company_id: @filters[:company_id]).select(:id))
    end
    relation = JrcCulture::Participation.where(version_id: versions.select(:id), grant_id: grants.select(:id))
    relation = relation.confirmed.or(relation.where(grant_id: grants.eligible.select(:id)))
    relation = relation.where(department: @filters[:department]) if @filters[:department].present?
    relation = relation.where(grant_id: matching_grants(grants)) if @filters[:culture_person_query].present?
    period(relation)
  end

  def matching_grants(grants)
    value = "%#{ApplicationRecord.sanitize_sql_like(@filters[:culture_person_query].to_s.first(120))}%"
    grants.joins(account_user: :user).where('users.name ILIKE ?', value).select(:id)
  end

  def period(relation)
    column = Arel.sql('COALESCE(jrc_culture_participations.confirmed_at, jrc_culture_participations.created_at)')
    relation = relation.where(column.gteq(day(:from))) if @filters[:from].present?
    relation = relation.where(column.lt(day(:to).next_day)) if @filters[:to].present?
    relation
  end

  def day(key)
    date = Date.iso8601(@filters.fetch(key))
    Time.find_zone!(TIMEZONE).local(date.year, date.month, date.day)
  rescue ArgumentError
    raise Invalid
  end

  def filtered
    rows = base
    case @filters[:state]
    when 'confirmed' then rows.confirmed
    when 'pending' then rows.where(confirmed_at: nil)
    else rows
    end
  end

  def summary(rows)
    total = rows.count
    confirmed = rows.confirmed.count
    distribution = rows.joins(grant: { unit: :operating_company })
                       .group('companies.id', 'companies.name', 'jrc_crm_business_units.id', 'jrc_crm_business_units.name', :department)
                       .pluck(Arel.sql('companies.id, companies.name, jrc_crm_business_units.id, jrc_crm_business_units.name,
                                        jrc_culture_participations.department, COUNT(*), COUNT(jrc_culture_participations.confirmed_at)'))
    {
      total: total, confirmed: confirmed, pending: total - confirmed, percentage: total.zero? ? 0 : (100.0 * confirmed / total).round(1),
      distribution: distribution.map do |company_id, company, unit_id, unit, department, count, done|
        { company_id: company_id, company: company, unit_id: unit_id, unit: unit, department: department, total: count, confirmed: done }
      end
    }
  end

  def with_details(rows)
    rows.includes(:version, grant: [{ unit: :operating_company }, { account_user: :user }])
        .order(Arel.sql('confirmed_at DESC NULLS LAST, jrc_culture_participations.id DESC'))
  end

  def present(row)
    grant = row.grant
    { id: row.id, collaborator: grant.account_user&.user&.name, user_id: grant.user_key,
      company: grant.unit.operating_company.name, unit: grant.unit.name, department: row.department,
      version: row.version.number, title: row.version.title, confirmed_at: row.confirmed_at }
  end
end
