Feedbin::Application.config.iap = {
  "com.feedbin.feedbin.one_month" => {
    time: 1.month
  },
  "com.feedbin.feedbin.six_months" => {
    time: 6.months
  },
  "com.feedbin.feedbin.one_year" => {
    time: 12.months
  },
}

if Rails.env.production?
  Feedbin::Application.config.iap_endpoint = "https://buy.itunes.apple.com/verifyReceipt"
else
  Feedbin::Application.config.iap_endpoint = "https://sandbox.itunes.apple.com/verifyReceipt"
end