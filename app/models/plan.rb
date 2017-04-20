class Plan < ApplicationRecord
  has_many :users

  def period
    name.gsub(/ly$/, '').downcase
  end

end
