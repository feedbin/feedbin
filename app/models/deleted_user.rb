class DeletedUser < ApplicationRecord
  def self.search(query)
    where("email like ?", "%#{query}%")
  end

  def stripe_url
    "https://manage.stripe.com/customers/#{customer_id}"
  end

  def deleted?
    true
  end
end
