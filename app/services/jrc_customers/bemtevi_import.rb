# frozen_string_literal: true

# Imports a reviewed registry into the native customer master. An ERP identity
# never grants messaging consent, merges people or reassigns existing contacts.
class JrcCustomers::BemteviImport
  class InvalidImport < StandardError; end

  ROW_FIELDS = %w[source_system source_id source_status source_status_label observed_at eligible_for_import review_reasons
                  snapshot_sha256 contact_data_source company contact_points addresses].freeze
  COMPANY_FIELDS = %w[name trade_name tax_id person_kind state_registration municipal_registration relationship_type active source].freeze
  ADDRESS_FIELDS = %w[address_type postal_code street number complement district city state country].freeze
  SUBRESOURCE_FIELDS = { 'contact_points' => %w[kind value], 'addresses' => ADDRESS_FIELDS + ['source_id'] }.freeze
  POINT_KINDS = (JrcCustomers::Identity::EMAIL_KINDS + JrcCustomers::Identity::PHONE_KINDS).freeze
  MAX_BYTES = 8_388_608
  MAX_ROWS = 5000

  def initialize(account:, actor:, content:)
    @account = account
    @actor = actor
    raise InvalidImport, 'Invalid dataset size or encoding' unless content.is_a?(String) && content.bytesize.between?(2, MAX_BYTES)

    @content = content.dup.force_encoding(Encoding::UTF_8)
    raise InvalidImport, 'Invalid dataset encoding' unless @content.valid_encoding?

    @sha256 = Digest::SHA256.hexdigest(@content)
  end

  def preview
    authorize!
    plan = build_plan
    token = verifier.generate(envelope(plan), expires_in: 15.minutes) if plan[:counts][:quarantined] < plan[:rows].length
    summary(plan).merge(token: token, sha256: @sha256, expires_in_seconds: 900)
  end

  def apply!(token:)
    authorize!
    received = verify_token!(token)
    @account.with_lock do
      authorize!
      apply_plan!(build_plan, received)
    end
  end

  private

  def authorize!
    raise Pundit::NotAuthorizedError unless @actor.is_a?(User) && @account.reload.active?

    member = @account.account_users.find_by(user_id: @actor.id)
    context = { account: @account, user: @actor, account_user: member }
    raise Pundit::NotAuthorizedError unless JrcCustomers::DirectoryPolicy.new(context, :directory).administer?
  end

  def verify_token!(token)
    raise InvalidImport, 'Invalid preview token' unless token.is_a?(String) && token.bytesize <= 8192

    payload = verifier.verified(token)
    received = payload.with_indifferent_access if payload.is_a?(Hash)
    expected = { account_id: @account.id, actor_id: @actor.id, sha256: @sha256 }.with_indifferent_access
    return received if received&.slice(*expected.keys) == expected

    raise InvalidImport, 'Preview expired or belongs to different data, account or actor'
  end

  def apply_plan!(plan, received)
    candidates = plan[:rows].reject { |row| row[:reason] }
    if candidates.length == received[:candidate_count] && candidates.all? { |row| row[:already_applied] }
      return summary(plan).merge(applied: 0, already_applied: candidates.length)
    end
    raise InvalidImport, 'Records changed since preview; preview again' unless received == envelope(plan).with_indifferent_access

    handler = ImportHandler.new(account: @account, actor: @actor, sha256: @sha256)
    candidates.each { |row| handler.call(row) }
    summary(plan).merge(applied: candidates.length, already_applied: 0)
  end

  def verifier
    Rails.application.message_verifier('jrc_bemtevi_customer_import')
  end

  def envelope(plan)
    { account_id: @account.id, actor_id: @actor.id, sha256: @sha256,
      candidate_count: plan[:rows].count { |row| row[:reason].nil? }, plan_sha256: Digest::SHA256.hexdigest(plan[:rows].to_json) }
  end

  def summary(plan)
    plan.slice(:counts, :quarantine_reasons, :point_quarantine_reasons, :address_quarantine_reasons)
  end

  def build_plan
    PlanBuilder.new(account: @account, content: @content, sha256: @sha256).call
  end

  class InputValidator
    def self.call(content)
      new.call(content)
    end

    def call(content)
      rows = JSON.parse(content, max_nesting: 12)
      raise InvalidImport, 'Dataset must contain one to 5000 customer objects' unless rows.is_a?(Array) && rows.length.between?(1, MAX_ROWS)

      rows.each { |row| validate_row!(row) }
      rows
    rescue JSON::ParserError
      raise InvalidImport, 'Invalid JSON dataset'
    end

    private

    def validate_row!(row)
      validate_keys!(row, ROW_FIELDS)
      validate_keys!(row['company'], COMPANY_FIELDS)
      validate_scalars!(row['company'].except('active'))
      SUBRESOURCE_FIELDS.each do |field, allowed|
        values = row.fetch(field, [])
        raise InvalidImport, 'Invalid customer subresources' unless values.is_a?(Array) && values.length <= 100

        values.each do |value|
          validate_keys!(value, allowed)
          validate_scalars!(value)
        end
      end
      validate_metadata!(row)
    end

    def validate_keys!(value, allowed)
      raise InvalidImport, 'Unsupported customer fields' unless value.is_a?(Hash) && (value.keys - allowed).empty?
    end

    def validate_scalars!(attributes)
      valid = attributes.values.all? { |value| value.nil? || (value.is_a?(String) && value.length <= 1024 && value.exclude?("\u0000")) }
      raise InvalidImport, 'Invalid customer scalar values' unless valid
    end

    def validate_metadata!(row)
      validate_scalars!(row.slice('source_system', 'source_id', 'source_status_label', 'observed_at', 'snapshot_sha256', 'contact_data_source'))
      reasons = row.fetch('review_reasons', [])
      raise InvalidImport, 'Invalid review reasons' unless reasons.is_a?(Array) && reasons.length <= 100 && reasons.all?(String)
    end
  end

  class SourceValidator
    def initialize(source_counts:, tax_counts:)
      @source_counts = source_counts
      @tax_counts = tax_counts
    end

    def call(row)
      return 'invalid_source' unless valid_source?(row)
      return 'duplicate_source_id' if @source_counts[row['source_id']] > 1

      eligibility_reason(row) || fiscal_reason(row) || observation_reason(row['observed_at'])
    end

    private

    def valid_source?(row)
      row['source_system'] == 'bemtevi' && row['source_id'].is_a?(String) && row['source_id'].match?(/\A[1-9][0-9]{0,15}\z/)
    end

    def eligibility_reason(row)
      return 'source_not_active' unless row['source_status'].is_a?(Integer) && row['source_status'].zero? && row.dig('company', 'active') == true
      return 'source_review_required' unless row['eligible_for_import'] == true && row.fetch('review_reasons', []).empty?

      nil
    end

    def fiscal_reason(row)
      tax = JrcCustomers::TaxIdentifier.normalize(row['company']['tax_id'])
      kind = row['company']['person_kind']
      return 'invalid_tax_id' unless valid_tax?(tax, kind)
      return 'duplicate_tax_id' if @tax_counts[tax] > 1

      nil
    end

    def valid_tax?(tax, kind)
      tax.present? && %w[organization individual].include?(kind) && JrcCustomers::TaxIdentifier.valid?(tax, person_kind: kind)
    end

    def observation_reason(value)
      observed = Time.iso8601(value.to_s)
      observed.between?(24.hours.ago, 5.minutes.from_now) ? nil : 'stale_or_future_observation'
    rescue ArgumentError
      'invalid_observation'
    end
  end

  class PlanBuilder
    def initialize(account:, content:, sha256:)
      @account = account
      @content = content
      @sha256 = sha256
    end

    def call
      rows = InputValidator.call(@content)
      build_indexes(rows)
      planned = rows.each_with_index.map { |row, index| plan_row(row, index + 1) }
      report(planned)
    end

    private

    def build_indexes(rows)
      sources = rows.map { |row| row['source_id'].to_s }.tally
      taxes = rows.filter_map { |row| JrcCustomers::TaxIdentifier.normalize(row.dig('company', 'tax_id')) }.tally
      @validator = SourceValidator.new(source_counts: sources, tax_counts: taxes)
      @companies = CompanyQuery.new(account: @account, sha256: @sha256)
      point_sources = Hash.new { |hash, key| hash[key] = [] }
      @resources = ResourceQuery.new(account: @account, point_sources: point_sources)
      index_points(rows, point_sources)
    end

    def index_points(rows, point_sources)
      rows.each do |row|
        Array(row['contact_points']).each do |raw|
          point = @resources.normalized_point(raw)
          point_sources[point[:key]] |= [row['source_id']] if point
        end
      end
    end

    def plan_row(row, line)
      result = { line: line, source_id: row['source_id'], observed_at: row['observed_at'] }
      reason = @validator.call(row)
      return result.merge(reason: reason) if reason

      company_plan = @companies.call(row)
      return result.merge(reason: company_plan[:reason]) if company_plan[:reason]

      candidate = company_plan.delete(:candidate)
      org = @account.contacts.find_by(identifier: "bemtevi:customer:#{row['source_id']}")
      result.merge(company_plan, resource_plan(row, candidate, org))
    end

    def resource_plan(row, candidate, org)
      points = Array(row['contact_points']).map { |point| @resources.plan_point(point, row['source_id'], candidate, org) }
      { provenance: row.slice('snapshot_sha256', 'contact_data_source', 'source_status'), points: points.uniq,
        addresses: Array(row['addresses']).map { |address| @resources.plan_address(address, candidate) } }
    end

    def report(planned)
      candidates = planned.reject { |row| row[:reason] }
      reasons = planned.filter_map { |row| row[:reason] }.tally
      counts = company_counts(candidates).merge(quarantined: reasons.values.sum,
                                                addresses_create: resource_create_count(candidates, :addresses, :id),
                                                contact_points_create: resource_create_count(candidates, :points, :point_id))
      { rows: planned, counts: counts, quarantine_reasons: reasons,
        point_quarantine_reasons: resource_reasons(candidates, :points), address_quarantine_reasons: resource_reasons(candidates, :addresses) }
    end

    def company_counts(rows)
      { companies_create: rows.count { |row| row[:company_id].nil? },
        companies_update: rows.count { |row| row[:company_id] && !row[:already_applied] },
        already_applied: rows.count { |row| row[:already_applied] } }
    end

    def resource_create_count(rows, resource, identifier)
      rows.sum { |row| row[resource].count { |entry| !entry[:reason] && entry[identifier].nil? } }
    end

    def resource_reasons(rows, resource)
      rows.flat_map { |row| row[resource].filter_map { |entry| entry[:reason] } }.tally
    end
  end

  class CompanyQuery
    def initialize(account:, sha256:)
      @account = account
      @sha256 = sha256
    end

    def call(row)
      source = @account.master_companies.where("custom_attributes -> 'bemtevi' ->> 'source_id' = ?", row['source_id']).to_a
      fiscal = fiscal_company(row.dig('company', 'tax_id'))
      company = source.first || fiscal
      reason = conflict_reason(row, source, fiscal, company)
      reason ? { reason: reason } : company_plan(row, company)
    end

    private

    def fiscal_company(tax)
      @account.master_companies.find_by("NULLIF(upper(regexp_replace(tax_id, '[^A-Za-z0-9]', '', 'g')), '') = ?",
                                        JrcCustomers::TaxIdentifier.normalize(tax))
    end

    def conflict_reason(row, source, fiscal, company)
      return 'duplicate_existing_source_id' if source.length > 1
      return 'company_identity_conflict' if source.first && fiscal && source.first.id != fiscal.id
      return existing_conflict(row, company) if company
      return 'unreviewed_name_match' if @account.master_companies.exists?(['lower(name) = ?', row['company']['name'].to_s.strip.downcase])

      nil
    end

    def existing_conflict(row, company)
      return 'internal_company_conflict' if company.relationship_type == 'internal'
      return 'company_identity_conflict' if company.tax_id.present? && normalized_tax(company.tax_id) != normalized_tax(row['company']['tax_id'])
      return 'company_identity_conflict' if company.person_kind != row['company']['person_kind']
      return 'source_binding_conflict' if conflicting_binding?(company.custom_attributes['bemtevi'], row['source_id'])

      nil
    end

    def conflicting_binding?(binding, source_id)
      binding.present? && (!binding.is_a?(Hash) || binding['source_id'].to_s != source_id)
    end

    def normalized_tax(value)
      JrcCustomers::TaxIdentifier.normalize(value)
    end

    def company_plan(row, company)
      stamp = company&.attributes&.slice('id', 'updated_at', 'custom_attributes')
      attributes = company_attributes(row, company)
      candidate = company || @account.master_companies.new
      candidate.assign_attributes(attributes)
      return { reason: 'invalid_company' } unless candidate.valid?

      { reason: nil, company_id: company&.id, company_stamp: stamp, candidate: candidate, attributes: attributes,
        already_applied: company&.custom_attributes&.dig('bemtevi', 'import_sha256') == @sha256 }
    end

    def company_attributes(row, company)
      attributes = row['company'].slice('name', 'trade_name', 'tax_id', 'person_kind', 'state_registration', 'municipal_registration')
      return attributes.merge('relationship_type' => 'customer', 'active' => true, 'source' => 'import') unless company

      attributes.select { |key, value| company[key].blank? && value.present? }
    end
  end

  class ResourceQuery
    def initialize(account:, point_sources:)
      @account = account
      @point_sources = point_sources
    end

    def normalized_point(raw)
      kind = raw['kind']
      return unless POINT_KINDS.include?(kind) && raw['value'].is_a?(String) && raw['value'].length <= 255

      value = JrcCustomers::Identity.point(kind, raw['value'])
      return unless value

      family = JrcCustomers::Identity::EMAIL_KINDS.include?(kind) ? 'email' : 'phone'
      { kind: kind, value: value, family: family, key: "#{family}:#{value}" }
    end

    def plan_point(raw, source_id, company, org)
      point = normalized_point(raw)
      return { reason: 'invalid_contact_point', source_digest: Digest::SHA256.hexdigest(raw.to_json) } unless point
      return point.merge(reason: 'shared_point_across_source_customers') if @point_sources[point[:key]].length > 1

      contact, reason = resolve_contact(point, source_id, company, org)
      return point.merge(reason: reason) if reason

      point.merge(point_state(point, contact))
    end

    def plan_address(raw, company)
      attributes = address_attributes(raw)
      result = { source_id: raw['source_id'], attributes: attributes }
      reason = address_reason(raw, attributes, company)
      return result.merge(reason: reason) if reason

      existing = company.persisted? ? company.addresses.where(account: @account).find_by(attributes) : nil
      result.merge(reason: nil, id: existing&.id, stamp: existing&.updated_at&.iso8601(6))
    end

    private

    def point_state(point, contact)
      existing = contact&.contact_points&.find_by(kind: point[:kind], normalized_value: point[:value])
      { reason: nil, contact_id: contact&.id, point_id: existing&.id,
        contact_stamp: record_stamp(contact, %w[id updated_at company_id blocked identifier additional_attributes]),
        point_stamp: record_stamp(existing, %w[id updated_at]) }
    end

    def record_stamp(record, fields)
      record&.attributes&.slice(*fields)
    end

    def address_attributes(raw)
      attributes = ADDRESS_FIELDS.index_with { |field| raw[field]&.strip.presence }
      attributes['address_type'] ||= 'other'
      attributes['country'] ||= 'BR'
      attributes
    end

    def resolve_contact(point, source_id, company, org)
      matches = JrcCustomers::IdentityResolver.new(account: @account).call(**{ point[:family].to_sym => point[:value] }).to_a
      return [nil, 'ambiguous_contact_point'] if matches.length > 1

      contact = matches.first
      return [contact, contact_reason(contact, company)] if contact
      return [nil, 'organizational_contact_conflict'] if org && !matching_organization?(org, company, source_id)

      [org, nil]
    end

    def contact_reason(contact, company)
      return 'contact_company_unconfirmed' if contact.company_id.nil?
      return 'contact_company_conflict' if contact.company_id != company.id

      nil
    end

    def matching_organization?(org, company, source_id)
      company.persisted? && org.company_id == company.id && org.additional_attributes['entity_type'] == 'company' &&
        org.additional_attributes['source_system'] == 'bemtevi' && org.additional_attributes['source_id'] == source_id
    end

    def address_reason(raw, attributes, company)
      return 'invalid_address_source_id' unless raw['source_id'].is_a?(String) && raw['source_id'].match?(/\A[1-9][0-9]{0,15}\z/)
      return 'empty_address' if attributes.slice('street', 'postal_code', 'city', 'district').values.all?(&:blank?)
      return 'invalid_address' unless JrcCustomers::Address.new(attributes.merge('account' => @account, 'company' => company)).valid?

      nil
    end
  end

  class ImportHandler
    def initialize(account:, actor:, sha256:)
      @account = account
      @actor = actor
      @sha256 = sha256
      @writer = JrcCustomers::CompanyWriter.new(account: account, actor: actor)
    end

    def call(row)
      company = row[:company_id] ? @account.master_companies.find(row[:company_id]) : @account.master_companies.new
      @writer.save!(company: company, attributes: row[:attributes])
      points, addresses = apply_resources!(company, row)
      binding = source_binding(company, row, points, addresses)
      @writer.save!(company: company, attributes: { custom_attributes: company.custom_attributes.merge('bemtevi' => binding) })
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: company, event_type: 'customer_import_applied',
                                  metadata: { source_system: 'bemtevi', source_id: row[:source_id], sha256: @sha256,
                                              contact_points: points.length, addresses: addresses.length })
    end

    private

    def apply_resources!(company, row)
      points = row[:points].reject { |point| point[:reason] }.map { |point| apply_point!(company, row[:source_id], point) }
      addresses = row[:addresses].reject { |address| address[:reason] }.map { |address| apply_address!(company, row, address) }
      [points, addresses]
    end

    def source_binding(company, row, points, addresses)
      previous = company.custom_attributes['bemtevi'] || {}
      previous.merge(row[:provenance], 'source_id' => row[:source_id], 'observed_at' => row[:observed_at], 'import_sha256' => @sha256,
                                       'contact_links' => merge_links(previous['contact_links'], points, %w[source_id contact_id point_id]),
                                       'address_links' => merge_links(previous['address_links'], addresses, %w[source_id address_id]),
                                       'pending_contact_points' => pending_resources(row[:points]),
                                       'pending_addresses' => pending_resources(row[:addresses]))
    end

    def merge_links(previous, current, fields)
      (Array(previous) + current).reverse.uniq { |link| link.values_at(*fields) }.reverse
    end

    def pending_resources(entries)
      entries.filter_map { |entry| entry.stringify_keys.except('key') if entry[:reason] }
    end

    def apply_address!(company, row, address)
      attributes = address[:attributes].merge('account' => @account)
      target = address[:id] ? company.addresses.find(address[:id]) : company.addresses.find_or_create_by!(attributes)
      { 'source_id' => address[:source_id], 'address_id' => target.id, 'observed_at' => row[:observed_at] }
    end

    def apply_point!(company, source_id, point)
      contact = contact_for!(company, source_id, point)
      target = contact.contact_points.find_or_create_by!(account: @account, kind: point[:kind], normalized_value: point[:value]) do |record|
        record.value = point[:value]
      end
      JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: contact, event_type: 'customer_contact_point_changed',
                                  metadata: { source_system: 'bemtevi', source_id: source_id, point_id: target.id, sha256: @sha256 })
      { 'contact_id' => contact.id, 'point_id' => target.id, 'kind' => point[:kind], 'source_id' => source_id }
    end

    def contact_for!(company, source_id, point)
      identifier = "bemtevi:customer:#{source_id}"
      contact = point[:contact_id] ? @account.contacts.find(point[:contact_id]) : @account.contacts.find_or_initialize_by(identifier: identifier)
      if contact.new_record?
        contact.assign_attributes(name: company.name, company_id: company.id, contact_type: 'customer', registration_status: 'registered',
                                  additional_attributes: { 'entity_type' => 'company', 'source_system' => 'bemtevi', 'source_id' => source_id })
      else
        contact.lock!
        raise InvalidImport, 'Contact changed since preview' unless contact.company_id == company.id
      end
      assign_primary_point(contact, identifier, point)
      contact.save! if contact.new_record? || contact.changed?
      contact
    end

    def assign_primary_point(contact, identifier, point)
      return unless contact.identifier == identifier && contact.additional_attributes['entity_type'] == 'company'

      primary = point[:family] == 'email' ? 'email' : 'phone_number'
      contact[primary] = point[:value] if contact[primary].blank?
    end
  end
end
