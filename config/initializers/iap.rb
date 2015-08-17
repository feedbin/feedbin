Feedbin::Application.config.iap = {
  "com.feedbin.feedbin.one_month" => {
    time: 31.days
  },
  "com.feedbin.feedbin.six_months" => {
    time: 183.days
  },
  "com.feedbin.feedbin.one_year" => {
    time: 365.days
  },
}

Feedbin::Application.config.iap_endpoint = {
  production: "https://buy.itunes.apple.com/verifyReceipt",
  sandbox: "https://sandbox.itunes.apple.com/verifyReceipt"
}
