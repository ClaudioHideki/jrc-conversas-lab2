# frozen_string_literal: true

class JrcCulture::Version < ApplicationRecord
  self.table_name = 'jrc_culture_versions'

  belongs_to :manual
  has_many :audiences, class_name: 'JrcCulture::Audience', dependent: :restrict_with_exception
  has_many :assets, class_name: 'JrcCulture::Asset', dependent: :restrict_with_exception
  has_many :participations, class_name: 'JrcCulture::Participation', dependent: :restrict_with_exception

  validates :title, presence: true, length: { maximum: 150 }
  validates :description, length: { maximum: 4_000 }
  validates :state, inclusion: { in: %w[draft published inactive withdrawn] }
  attr_readonly :manual_id, :number, :title, :description

  scope :published, -> { where(state: 'published') }
end
