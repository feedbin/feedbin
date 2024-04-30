class NewsletterSender < ApplicationRecord
  belongs_to :feed

  def search_data
    [token, full_token, email, name].join.downcase.gsub(/\s+/, "")
  end
end
