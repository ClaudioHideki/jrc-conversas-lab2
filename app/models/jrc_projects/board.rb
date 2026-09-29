module JrcProjects
  class Board < ApplicationRecord
    belongs_to :account
    belongs_to :project
    has_many :board_columns, -> { order(:position) }, dependent: :destroy
    validates :name, presence: true
  end
end
