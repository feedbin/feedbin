class AppStoreNotification < ApplicationRecord
  belongs_to :user

  def receipt_amount
    if plan == "monthly_pro_v1"
      5.99
    elsif plan == "yearly_pro_v1"
      59.9
    end
  end

  def receipt_date
    ms_to_date(data.safe_dig("data", "signedTransactionInfo", "purchaseDate")).to_formatted_s(:date)
  end

  def receipt_description
    if plan == "monthly_pro_v1"
      "Monthly"
    elsif plan == "yearly_pro_v1"
      "Yearly"
    end
  end

  def currency
    "USD"
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
