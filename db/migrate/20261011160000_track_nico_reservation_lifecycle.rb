class TrackNicoReservationLifecycle < ActiveRecord::Migration[7.1]
  def change
    [:jrc_nico_inferences, :jrc_nico_runs].each do |table|
      add_column table, :accounting, :jsonb, null: false, default: {}
      add_column table, :lease_expires_at, :datetime
    end
  end
end
