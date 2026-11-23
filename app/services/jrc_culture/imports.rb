# frozen_string_literal: true

class JrcCulture::Imports
  class Invalid < StandardError; end

  def initialize(access)
    @access = access
  end

  def scope
    @access.admin!
    JrcCulture::Import.where(account: @access.account, unit_id: @access.admin_units.select(:id))
  end

  def create!(unit_id:, file:)
    unit = @access.admin_units.find(unit_id)
    blob = JrcCulture::Files.upload!(file, kind: 'xlsx')
    JrcCulture::Workbook.rows(JrcCulture::Files.download(blob))
    @access.account.with_lock('FOR NO KEY UPDATE') do
      @access.admin_units.find(unit.id)
      run = scope.create!(unit: unit, blob: blob, actor_id: @access.user.id)
      JrcCulture::Event.record!(@access, 'import_uploaded', run)
      run
    end
  rescue StandardError
    JrcCulture::Files.discard_unowned(blob)
    raise
  end

  def preview(run)
    directory = @access.employee_directory(run.unit).select { |member| member.user.active_for_authentication? }
    by_email = directory.group_by { |member| member.user.email.to_s.downcase }
    by_login = directory.group_by { |member| member.user.email.to_s.downcase.split('@').first }
    rows = JrcCulture::Workbook.rows(JrcCulture::Files.download(run.blob))
    company = normalized_company(run.unit.operating_company.name)
    rows = rows.map { |row| match(row, by_email, by_login, company) }
    repeated = rows.filter_map { |row| row[:member_id] }.tally.select { |_id, count| count > 1 }
    rows.each do |row|
      next unless repeated.key?(row[:member_id])

      row.merge!(member_id: nil, status: 'duplicate')
    end
    rows
  end

  def apply!(id:, selections:)
    run = scope.find(id)
    return run if run.applied_at?

    # Recompute from the original protected bytes under current account and unit access.
    @access.account.with_lock('FOR NO KEY UPDATE') do
      run = scope.find(id)
      next run if run.applied_at?

      plans = preview(run).index_by { |row| row[:line] }
      requested = Array(selections).map { |entry| [Integer(entry[:line].to_s, 10), Integer(entry[:member_id].to_s, 10)] }
      raise Invalid if requested.empty? || requested.size > 1_000 || requested.map(&:first).uniq.size != requested.size

      requested.each do |line, member_id|
        row = plans[line]
        raise Invalid unless row && row[:status] == 'matched' && row[:member_id] == member_id

        @access.admin_units.find(run.unit_id)
        member = @access.eligible_member!(run.unit, member_id)
        JrcCulture::Roster.new(@access).enable!(unit: run.unit, member: member, department: row[:department])
      end
      run.update!(applied_at: Time.current, result: { applied: requested.size, skipped: plans.size - requested.size })
      JrcCulture::Event.record!(@access, 'import_applied', run)
      run
    end
  rescue ArgumentError, TypeError
    raise Invalid
  end

  private

  def normalized_company(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, '')
  end

  def match(row, by_email, by_login, company)
    email = row.fetch('EMAIL', '').downcase
    login = row.fetch('USUARIO', '').downcase
    matches = if email.present?
                by_email.fetch(email, [])
              elsif login.present?
                by_login.fetch(login, [])
              else
                []
              end
    conflicting = email.present? && by_login.fetch(login, []).any? { |member| matches.exclude?(member) }
    stated_company = normalized_company(row['EMPRESA REGISTRADA'])
    status = if stated_company.present? && stated_company != company
               'company_mismatch'
             elsif email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)
               'invalid_email'
             elsif conflicting || matches.size > 1
               'ambiguous'
             elsif matches.empty?
               'unmatched'
             else
               'matched'
             end
    target = matches.first if status == 'matched'
    { line: row.fetch('line'), email: email, login: login, member_id: target&.id, name: target&.user&.name,
      department: row.fetch('SETOR', '').first(120), status: status }
  end
end
