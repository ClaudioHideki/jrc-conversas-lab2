# frozen_string_literal: true

# An institutional identity is independent of its folder and immutable file versions.
class JrcContactCenter::AudioAsset < JrcContactCenter::ApplicationRecord
  include JrcContactCenter::AdministrativeAuditable

  belongs_to :unit, class_name: 'JrcContactCenter::Unit'
  belongs_to :folder, class_name: 'JrcContactCenter::AudioFolder', optional: true
  has_many :versions, class_name: 'JrcContactCenter::AudioVersion', inverse_of: :audio_asset, dependent: :restrict_with_error
  has_one :latest_version, lambda {
    select('DISTINCT ON (jrc_contact_center_audio_versions.audio_asset_id) jrc_contact_center_audio_versions.*')
      .order(:audio_asset_id, number: :desc)
  }, class_name: 'JrcContactCenter::AudioVersion', foreign_key: :audio_asset_id, inverse_of: :audio_asset, dependent: :restrict_with_error
  attr_readonly :account_id, :unit_id

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 1000 }
  validates :purpose, length: { maximum: 160 }
  validate :native_origin
  before_validation { self.name = name&.strip }

  private

  def native_origin
    errors.add(:unit, :invalid) unless unit&.account_id == account_id
    return unless folder

    errors.add(:folder, :invalid) unless folder.account_id == account_id && folder.unit_id == unit_id
  end
end
