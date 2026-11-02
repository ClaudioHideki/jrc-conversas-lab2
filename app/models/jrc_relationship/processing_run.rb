class JrcRelationship::ProcessingRun < ApplicationRecord
  self.table_name = 'jrc_relationship_processing_runs'
  belongs_to :account
  belongs_to :viewer, class_name: 'User'
  validates :access_signature, :started_at, presence: true
  validates :state, inclusion: { in: %w[running completed failed] }

  def self.latest_for(context, scope)
    where(account: context.account, viewer: context.user, access_signature: context.access_signature)
      .where('EXISTS (SELECT 1 FROM jsonb_array_elements_text(requested_ids) AS requested(value) ' \
             "WHERE requested.value::bigint IN (#{scope.reselect(:id).reorder(nil).to_sql}))").order(id: :desc).first
  end

  def summary(scope)
    ids = scope.where(id: requested_ids).pluck(:id).map(&:to_s)
    visible = outcomes.slice(*ids)
    { state: state, started_at: started_at, finished_at: finished_at, requested: ids.size,
      processed: visible.values.count('processed'), failed: visible.values.count { |value| value != 'processed' } }
  end
end
