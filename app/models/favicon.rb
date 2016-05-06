class Favicon < ActiveRecord::Base
  def data
    self[:data] || {}
  end
end
