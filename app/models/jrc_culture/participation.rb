# frozen_string_literal: true

class JrcCulture::Participation < ApplicationRecord
  self.table_name = 'jrc_culture_participations'

  belongs_to :version
  belongs_to :grant
  attr_readonly :version_id, :grant_id, :department

  scope :confirmed, -> { where.not(confirmed_at: nil) }
end
