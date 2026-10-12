# Server code registers read-only domain contracts; there is no client registration/eval/constantize API.
# No commercial adapters are installed in E2. Synthetic test registrations are removed after each suite.
class JrcApprovals::Catalog
  Entry = Struct.new(:key, :version, :model, :fields, :authorize, :capture, :policy_only, keyword_init: true)
  @entries = {}
  @mutex = Mutex.new

  class << self
    def register(key:, version:, model:, fields:, authorize:, capture:, policy_only: false)
      valid_model = policy_only == true ? model.nil? : model.is_a?(Class) && model < ApplicationRecord
      raise JrcApprovals::Error, 'INVALID_CATALOG' unless key.match?(/\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_.]*\z/) &&
        version.is_a?(Integer) && version.positive? && valid_model && [true, false].include?(policy_only) &&
        authorize.respond_to?(:call) && capture.respond_to?(:call)

      schema = JrcServiceDesk::CanonicalJson.normalize(fields).deep_dup
      raise JrcApprovals::Error, 'INVALID_CATALOG' unless schema.any? && schema.all? do |name, type|
        name.match?(/\A[a-z][a-z0-9_]*\z/) && %w[integer decimal string boolean money datetime].include?(type)
      end
      schema.each_value(&:freeze)
      entry = Entry.new(key: key, version: version, model: model, fields: schema.freeze,
        authorize: authorize, capture: capture, policy_only: policy_only).freeze
      @mutex.synchronize do
        raise JrcApprovals::Error, 'DUPLICATE_CATALOG' if @entries.key?(key)

        @entries[key] = entry
      end
      entry
    end

    def fetch(key)
      @mutex.synchronize { @entries.fetch(key) { raise JrcApprovals::Error, 'ADAPTER_NOT_INSTALLED' } }
    end

    def snapshot(account:, user:, key:, resource_id:)
      entry = fetch(key)
      raise JrcApprovals::Error, 'POLICY_TEMPLATE_ONLY' if entry.policy_only
      resource = entry.model.where(account_id: account.id).find(resource_id)
      raise Pundit::NotAuthorizedError unless entry.authorize.call(user, resource) == true

      data = JrcServiceDesk::CanonicalJson.normalize(entry.capture.call(resource))
      raise JrcApprovals::Error, 'INVALID_CONTEXT' unless data.keys.sort == %w[issuer_company_id business_unit_id values].sort

      JrcApprovals::Authorization.scope!(account, data['issuer_company_id'], data['business_unit_id'])
      raise JrcApprovals::Error, 'INVALID_CONTEXT' unless data['values'].keys.sort == entry.fields.keys.sort

      entry.fields.each { |field, type| JrcApprovals::Conditions.value!(type, data['values'][field]) }
      data.merge('resource_type' => entry.model.name, 'resource_id' => resource.id,
                 'origin' => { 'catalog_key' => key, 'catalog_version' => entry.version })
    end
  end
end
