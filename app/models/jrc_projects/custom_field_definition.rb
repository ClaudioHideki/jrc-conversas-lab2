module JrcProjects
  class CustomFieldDefinition < ApplicationRecord
    belongs_to :account
    belongs_to :project, optional: true
    validates :name, :field_type, presence: true
  end
end
