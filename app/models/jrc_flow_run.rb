# == Schema Information
#
# Table name: jrc_flow_runs
#
#  id              :bigint           not null, primary key
#  error           :string
#  event_key       :string           not null
#  finished_at     :datetime
#  graph           :jsonb            not null
#  reset_at        :datetime
#  settings        :jsonb            not null
#  status          :string           default("running"), not null
#  steps           :integer          default(0), not null
#  trace           :jsonb            not null
#  variables       :jsonb            not null
#  wake_at         :datetime
#  wake_version    :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  flow_id         :bigint           not null
#  last_message_id :bigint           default(0), not null
#  node_id         :string
#
# Indexes
#
#  idx_jrc_one_live_flow_per_conversation            (conversation_id) UNIQUE WHERE ((status)::text = ANY ((ARRAY['running'::character varying, 'waiting'::character varying, 'delayed'::character varying])::text[]))
#  index_jrc_flow_runs_on_account_id                 (account_id)
#  index_jrc_flow_runs_on_account_id_and_created_at  (account_id,created_at)
#  index_jrc_flow_runs_on_conversation_id            (conversation_id)
#  index_jrc_flow_runs_on_flow_id                    (flow_id)
#  index_jrc_flow_runs_on_flow_id_and_event_key      (flow_id,event_key) UNIQUE
#  index_jrc_flow_runs_on_status_and_wake_at         (status,wake_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (flow_id => jrc_flows.id)
#
class JrcFlowRun < ApplicationRecord
  include JrcRelationship::PlaybookFlowScheduling

  belongs_to :flow, class_name: 'JrcFlow'
  belongs_to :account
  belongs_to :conversation
  validates :event_key, presence: true, uniqueness: { scope: :flow_id }
  validates :status, inclusion: { in: %w[running waiting delayed completed paused failed] }
  scope :live, -> { where(status: %w[running waiting delayed]) }

  def snapshot
    as_json(only: %i[id status node_id trace error steps created_at finished_at wake_at]).merge(
      conversation_id: conversation.display_id, contact_name: conversation.contact.name
    )
  end
end
