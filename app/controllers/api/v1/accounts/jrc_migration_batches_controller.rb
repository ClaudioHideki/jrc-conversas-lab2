require 'csv'

class Api::V1::Accounts::JrcMigrationBatchesController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :authorize_migration!
  before_action :set_batch, except: [:index, :create]
  after_action :no_store
  rescue_from JrcMigrations::Error, with: :migration_error

  def index
    scope = JrcMigrations::Batch.where(account_id: Current.account.id).order(id: :desc)
    if params[:before].present?
      raise JrcMigrations::Error, 'INVALID_CURSOR' unless /\A[1-9]\d{0,18}\z/.match?(params[:before].to_s)

      scope = scope.where('id < ?', params[:before])
    end
    rows = scope.limit(51).to_a
    render json: { data: rows.first(50), next_cursor: rows.size > 50 ? rows[49].id : nil, catalog: JrcMigrations::Catalog::FIELDS }
  end

  def show
    render_batch
  end

  def events
    render json: event_page
  end

  def create
    input = request.request_parameters
    raise JrcMigrations::Error, 'INVALID_STAGING_INPUT' if (input.keys - %w[source domain rows mapping file_name]).any?

    @batch = JrcMigrations::Stage.new(account: Current.account, user: Current.user).call(
      source: input['source'], domain: input['domain'], rows: input['rows'], mapping: input.fetch('mapping', {}), file_name: input['file_name']
    )
    render_batch(status: :created)
  end

  def preview
    JrcMigrations::Preview.new(batch: @batch, user: Current.user).call
    render_batch
  end

  def execute
    JrcMigrations::Execute.new(batch: @batch, user: Current.user).call
    render_batch
  end

  def scan
    JrcMigrations::MediaScan.new(item: media_item, user: Current.user).call
    render_batch
  end

  def recover_media
    item = media_item
    media = JrcMigrations::MediaObject.where(account_id: Current.account.id, batch_id: @batch.id, item_id: item.id).order(:generation).last!
    JrcMigrations::MediaRecovery.new(media: media, user: Current.user).call
    render_batch
  end

  def reconciliation
    render json: JrcMigrations::Reconciliation.new(batch: @batch, user: Current.user).call
  end

  def accept
    JrcMigrations::Reconciliation.new(batch: @batch, user: Current.user).accept!(note: params[:note])
    render_batch
  end

  def errors
    body = CSV.generate do |csv|
      csv << %w[legacy_id status decision error_code]
      @batch.items.where(status: %w[blocked failed]).or(@batch.items.where(decision: %w[review reject])).order(:id).each do |item|
        csv << [csv_safe(item.legacy_id), item.status, item.decision, item.error_code]
      end
    end
    send_data body, type: 'text/csv', filename: "migration-#{@batch.id}-errors.csv"
  end

  private

  def authorize_migration!
    raise JrcMigrations::Error, 'MIGRATION_FORBIDDEN' unless Current.account.feature_enabled?('data_import')

    JrcMigrations::Access.authorize!(Current.account, Current.user)
  end

  def set_batch
    @batch = JrcMigrations::Batch.find_by!(account_id: Current.account.id, id: params[:id])
  end

  def render_batch(status: :ok)
    history = event_page
    render json: @batch.as_json.merge('items' => serialized_items,
                                      'events' => history[:data], 'next_event_cursor' => history[:next_cursor]), status: status
  end

  def serialized_items
    media = JrcMigrations::MediaObject.where(account_id: Current.account.id, batch_id: @batch.id).includes(:blob).order(:generation)
                                    .group_by(&:item_id).transform_values(&:last)
    @batch.items.order(:id).map do |item|
      item.as_json(except: [:raw_data, :before_data]).merge('normalized_data' => item.normalized_data.except('file_base64'),
                                                          'media' => media[item.id]&.public_projection)
    end
  end

  def media_item
    @batch.items.find_by!(account_id: Current.account.id, id: params[:item_id])
  end

  def event_page
    scope = @batch.events.order(id: :desc)
    if params[:before].present?
      raise JrcMigrations::Error, 'INVALID_CURSOR' unless /\A[1-9]\d{0,18}\z/.match?(params[:before].to_s)

      scope = scope.where('id < ?', params[:before])
    end
    rows = scope.limit(51).to_a
    { data: rows.first(50), next_cursor: rows.size > 50 ? rows[49].id : nil }
  end

  def migration_error(error)
    status = error.message == 'MIGRATION_FORBIDDEN' ? :forbidden : :unprocessable_entity
    render json: { code: error.message }, status: status
  end

  def no_store
    response.headers['Cache-Control'] = 'no-store'
  end

  def csv_safe(value)
    /\A[=+\-@\t\r]/.match?(value.to_s) ? "'#{value}" : value
  end
end
