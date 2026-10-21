require 'csv'

class Api::V1::Accounts::JrcCampaigns::CampaignsController < Api::V1::Accounts::JrcCampaigns::BaseController
  rescue_from JrcCustomers::CampaignFilter::InvalidFilter do |exception|
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  before_action :set_campaign, only: [:show, :update, :destroy, :launch, :pause, :resume, :cancel, :duplicate, :report, :export, :preview, :request_review, :approve]

  def request_review
    @campaign.request_review!
    render json: serialize(@campaign).merge(review_snapshot: @campaign.review_snapshot)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def approve
    @campaign.approve!(Current.user, params[:digest])
    render json: serialize(@campaign)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def index
    campaigns = scope.includes(:steps, :executions, campaign_inboxes: :inbox).order(created_at: :desc)
    render json: campaigns.map { |campaign| serialize(campaign) }
  end

  def analytics
    render json: JrcCampaigns::DashboardService.new(
      Current.account,
      period: params[:period],
      campaign_id: params[:campaign_id],
      delivery_channel: params[:delivery_channel]
    ).as_json
  end

  def audience_preview
    campaign = scope.new(audience_preview_params)
    render json: audience_preview_json(campaign, recipient_preview_params)
  end

  def test_message
    result = JrcCampaigns::TestMessageService.new(
      account: Current.account,
      user: Current.user,
      delivery_channel: test_message_params[:delivery_channel],
      phone_number: test_message_params[:phone_number],
      email: test_message_params[:email],
      inbox_id: test_message_params[:inbox_id],
      step: test_message_params[:step],
      idempotency_key: test_message_params[:idempotency_key],
      operator_confirmed: test_message_params[:operator_confirmed]
    ).perform
    render json: result
  rescue StandardError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  def show
    render json: serialize(@campaign)
  end

  def create
    campaign = scope.new(campaign_params)
    campaign.created_by = Current.user
    if campaign.save
      render json: serialize(campaign), status: :created
    else
      render json: { errors: campaign.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    return render_not_editable unless @campaign.editable?

    if @campaign.update(campaign_params)
      reschedule_pending_launch if @campaign.scheduled? && @campaign.saved_change_to_scheduled_at?
      render json: serialize(@campaign.reload)
    else
      render json: { errors: @campaign.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    return render_not_editable if @campaign.running? || @campaign.paused?

    @campaign.destroy!
    head :no_content
  end

  def launch
    @campaign.launch!
    render json: serialize(@campaign.reload)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages.presence || ['Selecione uma caixa de envio e adicione ao menos uma mensagem.'] },
           status: :unprocessable_entity
  end

  def pause
    @campaign.pause!
    render json: serialize(@campaign)
  end

  def resume
    @campaign.resume!
    render json: serialize(@campaign)
  end

  def cancel
    @campaign.cancel!
    render json: serialize(@campaign)
  end

  def duplicate
    copy = nil
    JrcCampaigns::Campaign.transaction do
      copy = scope.create!(duplicate_attributes)
      @campaign.campaign_inboxes.each do |link|
        copy.campaign_inboxes.create!(inbox: link.inbox, position: link.position, weight: link.weight, enabled: link.enabled)
      end
      @campaign.steps.each do |step|
        copy.steps.create!(step.attributes.except('id', 'campaign_id', 'created_at', 'updated_at'))
      end
    end
    render json: serialize(copy), status: :created
  end

  def preview
    render json: audience_preview_json(@campaign)
  end

  def report
    render json: JrcCampaigns::ReportService.new(@campaign, page: params[:page], per_page: params[:per_page]).as_json
  end

  def export
    report_scope = @campaign.recipients.includes(:inbox, :execution).order(:id)
    csv = CSV.generate(headers: true) do |output|
      output << ['Nome', 'Canal', 'Destino', 'Telefone', 'E-mail', 'Caixa', 'Execução', 'Status', 'Agendado em', 'Enviado em', 'Entregue em',
                 'Lido em', 'Respondido em', 'Erro']
      report_scope.find_each do |recipient|
        output << [
          recipient.name,
          @campaign.delivery_channel,
          recipient.destination,
          recipient.phone_number,
          recipient.email,
          recipient.inbox&.name,
          recipient.execution&.run_number,
          recipient.status,
          recipient.scheduled_at,
          recipient.sent_at,
          recipient.delivered_at,
          recipient.read_at,
          recipient.replied_at,
          recipient.error_message
        ]
      end
    end
    send_data csv, filename: "jrc-campanha-#{@campaign.id}-relatorio.csv", type: 'text/csv; charset=utf-8'
  end

  private

  def scope
    Current.account.jrc_campaigns
  end

  def set_campaign
    @campaign = scope.find(params[:id])
  end

  def audience_preview_params
    params.require(:campaign).permit(:audience_type, :delivery_channel, :inbox_id,
                                    campaign_inboxes_attributes: [:inbox_id, :enabled, :position], audience_config: {})
  end

  def test_message_params
    params.require(:test_message).permit(
      :delivery_channel,
      :phone_number,
      :email,
      :inbox_id,
      :idempotency_key,
      :operator_confirmed,
      step: [
        :kind, :subject, :body, :media_url, :file_name, :media_asset_id, :template_name, :template_namespace, :template_language,
        { template_params: {}, inbox_overrides: {} }
      ]
    )
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :delivery_channel, :trigger_type, :scheduled_at, :audience_type, :message_body, :inbox_id, :rotation_mode, :delay_min_seconds,
      :delay_max_seconds,
      :conversation_mode,
      audience_config: {}, sending_window: {}, recurrence_config: {}, follow_up_config: {},
      campaign_inboxes_attributes: [:id, :inbox_id, :position, :weight, :enabled, :_destroy],
      steps_attributes: [:id, :position, :kind, :subject, :body, :media_url, :file_name, :media_asset_id, :template_name, :template_namespace,
                         :template_language,
                         :delay_after_seconds, :only_if_no_reply, :follow_up_after_hours, :_destroy, { template_params: {}, inbox_overrides: {} }]
    )
  end

  def serialize(campaign)
    JrcCampaigns::CampaignSerializer.new(campaign).as_json
  end

  def audience_preview_json(campaign, recipient_options = {})
    preview = JrcCampaigns::AudienceResolver.new(campaign).preview
    response = preview.except(:entries, :selectable_entries).merge(
      sample: preview[:entries].first(20).map do |entry|
        recipient_json(entry, selected: true)
      end
    )
    return response unless ActiveModel::Type::Boolean.new.cast(recipient_options[:include_recipients])

    entries = filter_recipient_entries(preview[:selectable_entries], recipient_options[:recipient_search])
    page = [recipient_options[:recipient_page].to_i, 1].max
    per_page = (recipient_options[:recipient_per_page].presence || 50).to_i.clamp(1, 100)
    total = entries.size
    selected_keys = preview[:entries].map(&:selection_key).to_set
    response.merge(
      recipients: entries.slice((page - 1) * per_page, per_page).to_a.map do |entry|
        recipient_json(entry, selected: selected_keys.include?(entry.selection_key))
      end,
      recipient_pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: [(total.to_f / per_page).ceil, 1].max
      }
    )
  end

  def recipient_preview_params
    params.permit(:include_recipients, :recipient_search, :recipient_page, :recipient_per_page)
  end

  def filter_recipient_entries(entries, search)
    query = search.to_s.strip.downcase
    return entries if query.blank?

    entries.select do |entry|
      [entry.name, entry.phone_number, entry.email].compact.any? { |value| value.to_s.downcase.include?(query) }
    end
  end

  def recipient_json(entry, selected:)
    {
      selection_key: entry.selection_key,
      contact_id: entry.contact&.id,
      name: entry.name,
      phone_number: entry.phone_number,
      email: entry.email,
      source: entry.source,
      selected: selected
    }
  end

  def reschedule_pending_launch
    return unless @campaign.scheduled_at&.future?

    JrcCampaigns::LaunchJob.set(wait_until: @campaign.scheduled_at).perform_later(@campaign.id, @campaign.scheduled_at.to_i)
  end

  def render_not_editable
    render json: {
      errors: ['A campanha precisa estar em rascunho ou agendada para ser editada. Pause/cancele a execução antes de alterações estruturais.']
    }, status: :unprocessable_entity
  end

  def duplicate_attributes
    @campaign.attributes.slice(
      'delivery_channel', 'audience_type', 'audience_config', 'message_body', 'inbox_id', 'rotation_mode', 'delay_min_seconds',
      'delay_max_seconds', 'sending_window', 'conversation_mode', 'recurrence_config', 'follow_up_config'
    ).merge(
      'name' => "#{@campaign.name} (cópia)",
      'status' => 'draft',
      'trigger_type' => 'manual',
      'scheduled_at' => nil,
      'started_at' => nil,
      'paused_at' => nil,
      'completed_at' => nil,
      'last_execution_at' => nil,
      'created_by_id' => Current.user.id,
      'sent_count' => 0,
      'failed_count' => 0,
      'delivered_count' => 0,
      'read_count' => 0,
      'replied_count' => 0,
      'clicked_count' => 0
    )
  end
end
