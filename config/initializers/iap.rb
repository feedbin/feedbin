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

Feedbin::Application.config.iap_endpoint = {
  production: "https://buy.itunes.apple.com/verifyReceipt",
  sandbox: "https://sandbox.itunes.apple.com/verifyReceipt"
}
