# The controller authorizes the current configuration scope before this read.
# Stored version values remain immutable; paging never saves the draft.
class JrcRelationship::ConfigurationHistory
  FIELDS = %i[version weights rules actor_id created_at].freeze

  def initialize(account:, configuration:)
    raise ActiveRecord::RecordNotFound unless configuration.account_id == account.id

    @configuration = configuration
    @account = account
  end

  def call(source_version: nil, paginate: false, page: 1, per_page: 25)
    versions = @configuration.versions.where(account_id: @account.id).order(version: :desc)
    versions = versions.none unless @configuration.persisted?
    versions = versions.where(version: source_version) if source_version
    return { history: versions.limit(50).as_json(only: FIELDS) } unless paginate

    number = Integer(page.to_s, 10).clamp(1, 10_000)
    size = Integer(per_page.to_s, 10).clamp(1, 50)
    { history: versions.offset((number - 1) * size).limit(size).as_json(only: FIELDS),
      history_meta: { page: number, per_page: size, total: versions.count } }
  end
end
