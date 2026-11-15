require 'csv'

# Catalog loading is not policy publication and never grants approval authority.
class JrcApprovals::CatalogImport
  def initialize(account:, user:)
    @account, @user = account, user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def call(document:, format:, mappings:, people_mappings:, company_id: nil, unit_id: nil,
           dry_run: true, confirmed: false, key: nil, expected_digest: nil)
    actor = @authorization.authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
    raise JrcApprovals::Error, 'INVALID_IMPORT' unless mappings.is_a?(Hash) && people_mappings.is_a?(Hash) &&
      mappings.all? { |code, target| code.is_a?(String) && target.is_a?(String) && target.length <= 160 }
    @company_id, @unit_id = company_id, unit_id
    data = parse(document, format)
    input = { 'document' => data, 'mappings' => mappings, 'people_mappings' => people_mappings,
              'company_id' => company_id, 'unit_id' => unit_id }
    digest = JrcApprovals::Ledger.digest(input)
    JrcApprovals::Policy.transaction do
      JrcApprovals::Ledger.lock!(@account.id, 'catalog_import')
      people = resolve_people(data.fetch('people'), people_mappings)
      rows = data.fetch('approval_rules').map { |row| plan(row, mappings) }
      repeated = rows.select { |row| row['action'] == 'create' }.group_by { |row| row['catalog_key'] }.select { |_key, values| values.size > 1 }.keys
      rows.each { |row| row['action'] = 'conflict' if row['action'] == 'create' && repeated.include?(row['catalog_key']) }
      result = { 'rows' => rows, 'people' => people, 'counts' => rows.map { |row| row['action'] }.tally,
                 'dry_run' => dry_run, 'activated' => false, 'requests_created' => 0 }
      result['plan_digest'] = JrcApprovals::Ledger.digest(input.merge('rows' => rows))
      return result if dry_run

      raise JrcApprovals::Error, 'IMPORT_CONFIRMATION_REQUIRED' unless confirmed == true
      JrcApprovals::Ledger.key!(key)
      correlation = "catalog_import:#{actor.id}:#{key}"
      previous = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: correlation)
      if previous
        raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless previous.data['input_digest'] == digest

        return previous.data.fetch('result')
      end
      raise JrcApprovals::Error, 'VERSION_CONFLICT' unless expected_digest == result['plan_digest']
      raise JrcApprovals::Error, 'IMPORT_CONFLICT' if rows.any? { |row| row['action'] == 'conflict' }

      rows.select { |row| row['action'] == 'create' }.each do |row|
        module_key, event_key = row.fetch('catalog_key').split('.', 2)
        policy = JrcApprovals::Policies.new(account: @account, user: @user).create!(
          code: row['code'], name: row['name'], module_key: module_key, event_key: event_key,
          issuer_company_id: company_id, business_unit_id: unit_id,
          definition: { 'catalog_import' => { 'schema_version' => '1.0', 'source_digest' => digest,
                        'source_module' => row['source_module'], 'configuration_pending' => true } }
        )
        raise JrcApprovals::Error, 'IMPORT_UNSAFE_STATE' unless policy.state == 'draft' && !policy.enabled && policy.current_version_id.nil?

        row['policy_id'] = policy.id
      end
      JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'catalog_imported', key: correlation,
                                 data: { input_digest: digest, result: result })
      result
    end
  end

  private

  def parse(document, format)
    raise JrcApprovals::Error, 'INVALID_IMPORT' unless document.is_a?(String) && document.bytesize.between?(1, 262_144)

    data = if format == 'csv'
             csv = CSV.parse(document.delete_prefix("\uFEFF"), headers: true, col_sep: ';')
             raise JrcApprovals::Error, 'INVALID_IMPORT' unless %w[codigo modulo finalidade estado_importacao].all? { |h| csv.headers.include?(h) }

             { 'schema_version' => '1.0', 'activate' => false, 'people' => [], 'approval_rules' => csv.map do |row|
               raise JrcApprovals::Error, 'INVALID_IMPORT' unless row['estado_importacao'] == 'RASCUNHO_INATIVO'

               { 'code' => row['codigo'], 'module' => row['modulo'], 'title' => row['finalidade'], 'enabled' => false,
                 'workflow_state' => 'draft', 'approver_user_ids' => [], 'self_approval_allowed' => false }
             end }
           elsif format == 'json'
             JSON.parse(document)
           else
             raise JrcApprovals::Error, 'INVALID_IMPORT'
           end
    raise JrcApprovals::Error, 'INVALID_IMPORT' unless data.is_a?(Hash) && data['schema_version'] == '1.0' && data['activate'] == false &&
      data['people'].is_a?(Array) && data['people'].length <= 100 && data['approval_rules'].is_a?(Array) && data['approval_rules'].length.between?(1, 100)
    if data['tenant'].present? && !['RESOLVER_NO_AMBIENTE', @account.id.to_s].include?(data['tenant'].to_s)
      raise JrcApprovals::Error, 'INVALID_SCOPE'
    end
    rows = data['approval_rules']
    raise JrcApprovals::Error, 'INVALID_IMPORT' unless rows.all? do |row|
      row.is_a?(Hash) && row['code'].is_a?(String) && row['code'].match?(/\A[A-Z][A-Z0-9_]{1,100}\z/) &&
        row['title'].is_a?(String) && row['title'].length.between?(1, 200) && row['module'].is_a?(String) && row['module'].length <= 80 &&
        row['enabled'] == false && row['workflow_state'] == 'draft' && row['approver_user_ids'] == [] && row['self_approval_allowed'] == false
    end
    raise JrcApprovals::Error, 'INVALID_IMPORT' unless rows.map { |row| row['code'] }.uniq.length == rows.length

    data
  rescue JSON::ParserError, CSV::MalformedCSVError, EncodingError
    raise JrcApprovals::Error, 'INVALID_IMPORT'
  end

  def resolve_people(people, mappings)
    people.map do |person|
      raise JrcApprovals::Error, 'INVALID_IMPORT' unless person.is_a?(Hash) && person['full_name'].is_a?(String) && person['full_name'].length.between?(1, 200)

      id = mappings[person['full_name']]
      raise JrcApprovals::Error, 'INVALID_IMPORT_IDENTITY' if id.present? && !id.to_s.match?(/\A[1-9]\d*\z/)
      member = id.present? && @account.account_users.includes(:user).find_by(user_id: id)
      if id.present? && (!member || !member.user.active_for_authentication?)
        raise JrcApprovals::Error, 'INVALID_IMPORT_IDENTITY'
      end
      { 'name' => person['full_name'], 'user_id' => member ? member.user_id : nil, 'selected_user_name' => member ? member.user.name : nil,
        'status' => member ? 'reviewed_identity' : 'pending_identity', 'approval_authority_granted' => false }
    end
  end

  def plan(row, mappings)
    value = { 'code' => row['code'], 'name' => row['title'], 'source_module' => row['module'] }
    existing = JrcApprovals::Policy.find_by(account_id: @account.id, code: row['code'])
    if existing
      @authorization.authorize!('policy_manage', company_id: existing.issuer_company_id, unit_id: existing.business_unit_id)
      return value.merge('action' => 'preserved', 'policy_id' => existing.id, 'lock_version' => existing.lock_version)
    end
    key = mappings[row['code']]
    return value.merge('action' => 'pending_mapping') if key.blank?

    JrcApprovals::Catalog.fetch(key)
    module_key, event_key = key.split('.', 2)
    duplicate = JrcApprovals::Policy.where(account_id: @account.id, issuer_company_id: @company_id, business_unit_id: @unit_id,
                                         module_key: module_key, event_key: event_key).exists?
    value.merge('catalog_key' => key, 'action' => duplicate ? 'conflict' : 'create')
  rescue JrcApprovals::Error => error
    raise unless error.code == 'ADAPTER_NOT_INSTALLED'

    value.merge('action' => 'pending_adapter')
  end
end
