class AppStoreNotification < ApplicationRecord
  belongs_to :user

  # Apple sends the price in milliunits of the transaction's currency. Prefer
  # it: a price list kept in Ruby has to be updated in lockstep with the
  # products and cannot be right for a grandfathered customer. The two literals
  # remain for transactions that predate price in the payload.
  LEGACY_PRICES = {
    "monthly_pro_v1" => 5.99,
    "yearly_pro_v1"  => 59.9
  }

  def receipt_amount
    if (price = transaction["price"])
      price / 1000.0
    else
      LEGACY_PRICES[plan]
    end
  end

  def receipt_date
    ms_to_date(data.safe_dig("data", "signedTransactionInfo", "purchaseDate")).to_formatted_s(:date)
  end

  # Every product id the apps sell names its own billing period. Enumerating
  # two of the seven left the other five -- all four podcast subscriptions
  # among them -- rendering a receipt with a blank description.
  def receipt_description
    return nil unless AppStoreNotificationProcessor::PRODUCTS.key?(plan)
    plan.start_with?("monthly") ? "Monthly" : "Yearly"
  end

  def currency
    transaction["currency"] || "USD"
  end

  def transaction
    data.safe_dig("data", "signedTransactionInfo") || {}
  end

  def purchase_date
    ms_to_date data.safe_dig("data", "signedTransactionInfo", "purchaseDate")
  end

  def ms_to_date(ms)
    Time.at(ms / 1000)
  end

  def plan
    data.safe_dig("data", "signedTransactionInfo", "productId")
  end
end
