# == Schema Information
#
# Table name: jrc_nico_commands
#
#  id               :bigint           not null, primary key
#  approved_at      :datetime
#  arguments        :jsonb            not null
#  message          :text             not null
#  reply            :text
#  result           :jsonb            not null
#  status           :string           default("planning"), not null
#  tool             :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  request_id       :uuid             not null
#  session_id       :bigint           not null
#  source_notice_id :bigint
#
# Indexes
#
#  index_jrc_nico_commands_on_session_id                 (session_id)
#  index_jrc_nico_commands_on_session_id_and_request_id  (session_id,request_id) UNIQUE
#  index_jrc_nico_commands_on_source_notice_id           (source_notice_id)
#
# Foreign Keys
#
#  fk_rails_...  (session_id => jrc_nico_sessions.id) ON DELETE => cascade
#  fk_rails_...  (source_notice_id => jrc_nico_notices.id) ON DELETE => nullify
#
class JrcNico::Command < ApplicationRecord
  self.table_name = 'jrc_nico_commands'
  belongs_to :session, class_name: 'JrcNico::Session'
  belongs_to :source_notice, class_name: 'JrcNico::Notice', optional: true
  has_one :broker_send_operation, class_name: 'JrcNico::BrokerSendOperation', dependent: :nullify
  after_commit :publish_notice, on: [:create, :update]
  validates :request_id, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i }
  validates :message, presence: true, length: { maximum: 4000 }
  validates :status, inclusion: { in: %w[planning awaiting_confirmation executing browser_pending succeeded failed cancelled unknown] }

  def snapshot
    slice(:id, :request_id, :status, :tool, :arguments, :result, :reply, :created_at).merge(
      source_notice_id: source_notice_id, source_contact: source_notice&.conversation&.contact&.name,
      source_conversation_id: source_notice&.conversation&.display_id,
      authorization: execution_context['authorization'], result: current_result
    )
  end

  def current_result
    operation = broker_send_operation
    return result unless operation

    result.merge('broker_send' => operation.receipt.as_json)
  end

  def publish_notice
    return unless previous_changes.key?('status')

    JrcNico::Notice.command_changed!(self)
    if source_notice_id.nil? && execution_context['workflow_id'] && status == 'succeeded' && JrcNico::ToolCatalog::TOOLS.dig(tool, 2) == true
      JrcNico::ContinueCommandJob.perform_later(id)
    end
  end
end
