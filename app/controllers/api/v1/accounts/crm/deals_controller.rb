module Api
  module V1
    module Accounts
      module Crm
        class DealsController < BaseController
          before_action :set_deal, except: [:index, :create]

          def index
            deals = visible_to_current_user(crm_scope.jrc_crm_deals)
            deals = deals.where.not(status: 'archived') unless params[:status].present?
            deals = deals.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
            deals = deals.where(stage_id: params[:stage_id]) if params[:stage_id].present?
            deals = deals.where(owner_id: params[:owner_id]) if params[:owner_id].present?
            deals = deals.where(status: params[:status]) if params[:status].present?

            if params[:conversation_id].present?
              deals = deals
                        .joins(:deal_conversations)
                        .where(
                          jrc_crm_deal_conversations: {
                            conversation_id: params[:conversation_id]
                          }
                        )
            end

            if params[:search].present?
              deals = deals.where(
                'title ILIKE :q',
                q: "%#{params[:search]}%"
              )
            end

            deals = deals
                      .includes(
                        :pipeline,
                        :stage,
                        :owner,
                        :team,
                        :contact,
                        :contacts,
                        :proposals,
                        :products,
                        :deal_products,
                        :activities,
                        deal_conversations: :conversation
                      )
                      .order(updated_at: :desc)

            serialized_deals = deals.map do |deal|
              JrcCrm::DealSerializer.new(deal).as_json
            end

            render json: serialized_deals
          end

          def show
            render json: JrcCrm::DealSerializer.new(@deal).as_json
          end

          def create
            attributes = deal_params
            conversation_id = attributes.delete(:conversation_id)

            conversation =
              if conversation_id.present?
                crm_scope.conversations
                         .includes(:inbox, :contact)
                         .find(conversation_id)
              end

            if conversation
              attributes[:contact_id] ||= conversation.contact_id

              if attributes[:source].blank?
                attributes[:source] = source_from_conversation(conversation)
              end
            end

            deal = crm_scope.jrc_crm_deals.new(attributes)
            deal.owner ||= conversation&.assignee || Current.user

            JrcCrm::Deal.transaction do
              deal.save!
              create_initial_products!(deal)
              create_initial_activity!(deal)

              link_conversation!(deal, conversation_id) if conversation_id.present?
            end

            render json: JrcCrm::DealSerializer.new(deal).as_json,
                   status: :created
          rescue ActiveRecord::RecordInvalid => e
            render json: {
              errors: e.record.errors.full_messages
            }, status: :unprocessable_entity
          end

          def update
            attributes = deal_params
            conversation_id = attributes.delete(:conversation_id)

            # Serialize source edits with Linker, which locks this deal before linking.
            updated = @deal.with_lock do
              saved = @deal.update(attributes)
              link_conversation!(@deal, conversation_id) if saved && conversation_id.present?
              saved
            end

            if updated
              render json: JrcCrm::DealSerializer.new(@deal).as_json
            else
              render json: {
                errors: @deal.errors.full_messages
              }, status: :unprocessable_entity
            end
          end

          def move_stage
            stage = crm_scope.jrc_crm_stages.find(params[:stage_id])

            if stage.is_lost?
              lost_reason =
                crm_scope.jrc_crm_lost_reasons.find(params[:lost_reason_id])

              @deal.assign_attributes(
                lost_reason: lost_reason,
                lost_reason_note: params[:lost_reason_note]
              )
            end

            result = JrcCrm::DealPipelineService.new(
              deal: @deal,
              stage: stage,
              actor: Current.user
            ).call

            if result[:success]
              render json: {
                message: 'Stage updated',
                deal: JrcCrm::DealSerializer.new(result[:deal]).as_json
              }
            else
              render json: {
                error: result[:error]
              }, status: :unprocessable_entity
            end
          end

          def win
            stage = @deal.pipeline.stages.active.find_by!(is_won: true)

            render_pipeline_result(
              JrcCrm::DealPipelineService.new(
                deal: @deal,
                stage: stage,
                actor: Current.user
              ).call
            )
          end

          def lose
            reason =
              crm_scope.jrc_crm_lost_reasons.find(params[:lost_reason_id])

            @deal.assign_attributes(
              lost_reason: reason,
              lost_reason_note: params[:lost_reason_note]
            )

            stage = @deal.pipeline.stages.active.find_by!(is_lost: true)

            render_pipeline_result(
              JrcCrm::DealPipelineService.new(
                deal: @deal,
                stage: stage,
                actor: Current.user
              ).call
            )
          end

          private

          def set_deal
            @deal =
              visible_to_current_user(crm_scope.jrc_crm_deals)
              .includes(
                :pipeline,
                :stage,
                :owner,
                :team,
                :contact,
                :contacts,
                :proposals,
                :products,
                :deal_products,
                :activities,
                deal_conversations: :conversation
              )
              .find(params[:id])
          end

          def deal_params
            allowed = [
              :title,
              :pipeline_id,
              :stage_id,
              :value_cents,
              :currency,
              :contact_id, :company_id, :organization_id,
              :conversation_id,
              :team_id,
              :source,
              :description,
              :expected_close_at,
              :probability
            ]

            allowed << :owner_id if crm_admin?

            attributes = params.require(:deal).permit(*allowed)

            if attributes[:expected_close_at].present?
              attributes[:expected_close_at] =
                parse_crm_time(attributes[:expected_close_at])
            end

            attributes
          end

          def create_initial_products!(deal)
            items = params.permit(items: [:product_id, :quantity, :unit_price_cents, :discount_cents])[:items] || []
            items.each do |values|
              product = crm_scope.jrc_crm_products.active.find(values.fetch(:product_id))
              deal.deal_products.create!(values.merge(product: product, description_snapshot: product.description))
            end
            deal.update!(value_cents: deal.deal_products.sum(:total_cents)) if items.any?
          end

          def create_initial_activity!(deal)
            return unless params[:next_activity].present?
            attrs = params.require(:next_activity).permit(:title, :activity_type, :due_at)
            attrs[:due_at] = parse_crm_time(attrs[:due_at]) if attrs[:due_at].present?
            activity = crm_scope.jrc_crm_activities.new(attrs.merge(deal: deal, user: Current.user))
            result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: Current.user).call
            raise ActiveRecord::RecordInvalid, activity unless result[:success]
          end

          def source_from_conversation(conversation)
            channel = conversation.inbox&.channel_type.to_s

            case channel
            when /Whatsapp|WhatsApp/i
              'whatsapp'
            when /Email/i
              'email'
            when /Facebook/i
              'facebook'
            when /Instagram/i
              'instagram'
            when /WebWidget|Website/i
              'webchat'
            when /Voice|Twilio|Phone/i
              'ligacoes'
            else
              if conversation.inbox&.name.to_s.match?(/whatsapp calling/i)
                'ligacoes_whatsapp'
              else
                'outro'
              end
            end
          end

          def link_conversation!(deal, conversation_id)
            conversation = crm_scope.conversations.find(conversation_id)

            if deal.contact_id.present? &&
               conversation.contact_id != deal.contact_id
              raise ActiveRecord::RecordNotFound,
                    'Conversa não pertence ao contato selecionado'
            end

            deal.link_conversation!(conversation, Current.user)
          end

          def render_pipeline_result(result)
            if result[:success]
              render json:
                JrcCrm::DealSerializer.new(result[:deal]).as_json
            else
              render json: {
                error: result[:error]
              }, status: :unprocessable_entity
            end
          end
        end
      end
    end
  end
end
