class Api::V1::Accounts::JrcCampaigns::TestAuthorizationsController < Api::V1::Accounts::JrcCampaigns::BaseController
  def index
    render json: scope.order(id: :desc).limit(50).map { |authorization| serialize(authorization) }
  end

  def create
    attributes = params.require(:test_authorization).permit(:inbox_id, :phone_number, :evidence, :operator_confirmed)
    unless attributes.delete(:operator_confirmed) == true
      return render json: { errors: ['Confirme a autorização do titular para uma única solicitação de teste.'] }, status: :unprocessable_entity
    end

    inbox = Current.account.inboxes.find(attributes[:inbox_id])
    connector = JrcCampaigns::EvolutionConnector.for(inbox)
    return render json: { errors: ['Selecione uma caixa Evolution configurada.'] }, status: :unprocessable_entity unless connector

    authorization = scope.new(attributes.merge(recorded_by: Current.user, granted_at: Time.current,
                                                connector_snapshot: connector.public_configuration.slice(*JrcCampaigns::TestAuthorization::IDENTITY_FIELDS)))
    if authorization.save
      render json: serialize(authorization), status: :created
    else
      render json: { errors: authorization.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { errors: ['Já existe uma autorização de teste disponível para este destinatário e caixa.'] }, status: :unprocessable_entity
  end

  def destroy
    scope.find(params[:id]).update!(revoked_at: Time.current)
    head :no_content
  end

  private

  def scope
    JrcCampaigns::TestAuthorization.where(account: Current.account)
  end

  def serialize(authorization)
    authorization.as_json(only: [:id, :inbox_id, :phone_number, :evidence, :recorded_by_id, :granted_at, :consumed_at, :revoked_at, :test_delivery_id]).merge(
      sender_number: authorization.connector_snapshot['sender_number']
    )
  end
end
