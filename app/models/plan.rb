class Plan < ApplicationRecord
  has_many :users

  def period
    name.gsub(/ly$/, "").downcase
  end

  def price_in_cents
    price.to_i * 100
  end
end
