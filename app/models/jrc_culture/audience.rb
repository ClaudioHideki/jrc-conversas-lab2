# frozen_string_literal: true

class JrcCulture::Audience < ApplicationRecord
  self.table_name = 'jrc_culture_audiences'

  belongs_to :version
  belongs_to :unit, class_name: 'JrcCrm::BusinessUnit', optional: true
  attr_readonly :version_id, :unit_id
end
