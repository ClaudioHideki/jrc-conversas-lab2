# frozen_string_literal: true

class JrcCulture::Event < ApplicationRecord
  self.table_name = 'jrc_culture_events'

  belongs_to :account

  def self.record!(access, action, subject)
    create!(account: access.account, actor_id: access.user.id, action: action,
            subject_type: subject.class.name, subject_id: subject.id)
  end

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }
end
