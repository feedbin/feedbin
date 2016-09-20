class Favicon < ApplicationRecord
  def data
    self[:data] || {}
  end
end
