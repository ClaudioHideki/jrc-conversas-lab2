# frozen_string_literal: true

# Abstract ownership contract only. No operational table is introduced in CP1.
class JrcServiceDesk::Base < ApplicationRecord
  self.abstract_class = true

  belongs_to :account, optional: false
end
