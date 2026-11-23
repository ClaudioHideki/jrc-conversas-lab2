# frozen_string_literal: true

class JrcCulture::Manual < ApplicationRecord
  self.table_name = 'jrc_culture_manuals'

  belongs_to :account
  has_many :versions, class_name: 'JrcCulture::Version', dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 150 }
end
