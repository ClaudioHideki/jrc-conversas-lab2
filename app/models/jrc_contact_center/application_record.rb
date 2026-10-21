# frozen_string_literal: true

class JrcContactCenter::ApplicationRecord < ApplicationRecord
  self.abstract_class = true
  self.table_name_prefix = 'jrc_contact_center_'

  belongs_to :account
end
