# frozen_string_literal: true

class JrcCulture::Asset < ApplicationRecord
  self.table_name = 'jrc_culture_assets'

  belongs_to :version
  belongs_to :blob, class_name: 'ActiveStorage::Blob'
  validates :kind, inclusion: { in: %w[pdf pptx] }
  attr_readonly :version_id, :blob_id, :kind
end
