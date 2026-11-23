# frozen_string_literal: true

class JrcCulture::Import < ApplicationRecord
  self.table_name = 'jrc_culture_imports'

  belongs_to :account
  belongs_to :unit, class_name: 'JrcCrm::BusinessUnit'
  belongs_to :blob, class_name: 'ActiveStorage::Blob'
end
