require 'csv'
require 'digest'

# Companies use the master table. Contact CSV imports keep Chatwoot's existing job.
# Preview is read-only; apply requires the exact file and signed, actor/account-bound preview.
class JrcCustomers::CompanyImport
  class InvalidImport < StandardError; end
  FIELDS = %w[id name person_kind trade_name tax_id state_registration municipal_registration segment size website domain email
              phone_number source economic_group parent_company_id owner_id relationship_type active description].freeze
  MAX_BYTES = 1_048_576
  MAX_ROWS = 500

  def initialize(account:, actor:, content:)
    @account, @actor, @content = account, actor, content
    raise InvalidImport, 'CSV exceeds 1 MiB' if content.bytesize > MAX_BYTES
    @content = content.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    raise InvalidImport, 'CSV must be valid UTF-8' unless @content.valid_encoding?
  end

  def preview
    result = plan
    result.merge(token: result[:errors].empty? ? verifier.generate(envelope(result), expires_in: 15.minutes) : nil,
                 max_rows: MAX_ROWS, expires_in_seconds: 900)
  end

  def apply!(token:)
    raise InvalidImport, 'Invalid preview token' unless token.is_a?(String) && token.bytesize <= 4096
    payload = verifier.verified(token)
    received = payload.is_a?(Hash) ? payload.with_indifferent_access : nil
    raise InvalidImport, 'Preview expired or invalid; preview again' unless received

    @account.with_lock do
      result = plan
      raise InvalidImport, 'File, user or records changed since preview; preview again' unless received == envelope(result).with_indifferent_access
      raise InvalidImport, 'Resolve all preview errors before applying' if result[:errors].any?

      ids = result[:rows].map do |row|
        company = row[:company_id] ? @account.master_companies.find(row[:company_id]) : @account.master_companies.new
        JrcCustomers::CompanyWriter.new(account: @account, actor: @actor).save!(company: company, attributes: row[:attributes])
        company.id
      end
      if ids.any?
        JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @account.master_companies.find(ids.first),
                                    event_type: 'customer_import_applied', metadata: { sha256: Digest::SHA256.hexdigest(@content), company_ids: ids })
      end
      { applied: ids.length, company_ids: ids }
    end
  end

  private

  def verifier
    Rails.application.message_verifier('jrc_customer_master_import')
  end

  def envelope(result)
    { account_id: @account.id, actor_id: @actor.id, sha256: Digest::SHA256.hexdigest(@content),
      plan_sha256: Digest::SHA256.hexdigest(JSON.generate(result)) }
  end

  def plan
    parsed = CSV.parse(@content, headers: true, skip_blanks: true, field_size_limit: 65_536)
    raise InvalidImport, "Maximum #{MAX_ROWS} rows" if parsed.size > MAX_ROWS
    raise InvalidImport, 'CSV is empty' if parsed.empty?
    headers = Array(parsed.headers).map { |header| header.to_s.strip }
    raise InvalidImport, 'CSV must contain name and only supported headers; duplicate headers are not allowed' unless headers.include?('name') && (headers - FIELDS).empty? && headers.uniq.size == headers.size

    seen_ids, seen_tax, seen_domains = [], [], []
    result = { rows: [], errors: [] }
    parsed.each_with_index do |row, index|
      begin
        attrs = row.to_h.transform_keys { |key| key.to_s.strip }.transform_values { |value| value.to_s.strip.presence }
        id = attrs.delete('id')
        tax = JrcCustomers::TaxIdentifier.normalize(attrs['tax_id'])
        company = id.present? ? @account.master_companies.find(Integer(id, 10)) : nil
        by_tax = tax.present? ? @account.master_companies.find_by(tax_id: tax) : nil
        raise InvalidImport, 'ID and CPF/CNPJ point to different companies' if company && by_tax && company.id != by_tax.id
        company ||= by_tax
        if company.nil? && @account.master_companies.where('lower(name) = ?', attrs['name'].to_s.downcase).exists?
          raise InvalidImport, 'Matching name is not an identity: supply the existing id or review the company name'
        end
        raise InvalidImport, 'Same company appears more than once in CSV' if company && seen_ids.include?(company.id)
        raise InvalidImport, 'Repeated CPF/CNPJ in CSV' if tax && seen_tax.include?(tax)
        domain = attrs['domain']&.downcase
        raise InvalidImport, 'Repeated domain in CSV' if domain && seen_domains.include?(domain)
        seen_ids << company.id if company
        seen_tax << tax if tax
        seen_domains << domain if domain
        %w[parent_company_id owner_id].each { |key| attrs[key] = Integer(attrs[key], 10) if attrs[key].present? }
        if attrs.key?('active')
          raise InvalidImport, 'active must be true or false' unless %w[true false].include?(attrs['active'])
          attrs['active'] = attrs['active'] == 'true'
        end
        company ||= @account.master_companies.new(relationship_type: 'prospect')
        attrs['relationship_type'] ||= company.relationship_type
        original_stamp = company.persisted? ? company.updated_at.iso8601(6) : nil
        company.assign_attributes(attrs)
        raise InvalidImport, company.errors.full_messages.join('; ') unless company.valid?
        result[:rows] << { line: index + 2, action: company.persisted? ? 'update' : 'create', company_id: company.id,
                           updated_at: original_stamp, attributes: attrs }
      rescue InvalidImport, ActiveRecord::RecordNotFound, ArgumentError => error
        result[:errors] << { line: index + 2, error: error.message }
      end
    end
    result
  rescue CSV::MalformedCSVError => error
    raise InvalidImport, error.message
  end
end
