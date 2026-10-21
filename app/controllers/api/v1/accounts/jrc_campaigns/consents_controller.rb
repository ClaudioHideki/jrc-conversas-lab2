class Api::V1::Accounts::JrcCampaigns::ConsentsController < Api::V1::Accounts::JrcCampaigns::BaseController
  def index
    render json: scope.includes(:superseding_consent).order(created_at: :desc).map { |consent| serialize(consent) }
  end

  def create
    attributes = params.require(:consent).permit(:phone_number, :evidence, :operator_confirmed, :supersedes_id)
    unless attributes[:operator_confirmed] == true
      return render json: { errors: ['Confirme a autorização contínua do titular para testes e campanhas WhatsApp.'] }, status: :unprocessable_entity
    end

    consent = scope.new(phone_number: JrcCampaigns::PhoneNormalizer.call(attributes[:phone_number]), evidence: attributes[:evidence],
                        recorded_by: Current.user, granted_at: Time.current, purpose: 'whatsapp_campaigns')
    Current.account.with_lock do
      previous = scope.where(phone_number: consent.phone_number, revoked_at: nil).lock.first
      if previous
        raise ArgumentError, 'Já existe consentimento contínuo ativo para este telefone.' if previous.purpose == 'whatsapp_campaigns'
        unless attributes[:supersedes_id].to_s == previous.id.to_s
          raise ArgumentError, 'Use Registrar nova autorização no registro histórico e informe a nova evidência do titular.'
        end

        previous.update!(revoked_at: Time.current)
        consent.supersedes = previous
      elsif attributes[:supersedes_id].present?
        raise ArgumentError, 'O registro anterior mudou. Recarregue os consentimentos antes de confirmar.'
      end
      consent.save!
    end
    render json: serialize(consent), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  def destroy
    Current.account.with_lock do
      consent = scope.find(params[:id])
      consent.update!(revoked_at: Time.current) unless consent.revoked_at
    end
    head :no_content
  end

  def import_preview
    render json: importer.preview
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  def import_csv
    unless params[:operator_confirmed] == true
      return render json: { errors: ['Confirme a autorização contínua de todos os titulares do arquivo.'] }, status: :unprocessable_entity
    end

    render json: importer.import!, status: :created
  rescue ArgumentError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def importer
    JrcCampaigns::ConsentImporter.new(account: Current.account, user: Current.user, csv: params.require(:csv))
  end

  def scope
    JrcCampaigns::Consent.where(account: Current.account)
  end

  def fields
    [:id, :phone_number, :evidence, :purpose, :granted_at, :recorded_by_id, :revoked_at, :supersedes_id]
  end

  def serialize(consent)
    consent.as_json(only: fields).merge(superseded_by_id: consent.superseding_consent&.id)
  end
end
