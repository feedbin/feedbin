Feedbin::Application.config.iap = {
  "com.feedbin.feedbin.one_month" => {
    time: 31.days,
    amount: 399,
    name: "One Month",
  },
  "com.feedbin.feedbin.six_months" => {
    time: 183.days,
    amount: 1999,
    name: "Six Months",
  },
  "com.feedbin.feedbin.one_year" => {
    time: 365.days,
    amount: 3999,
    name: "One Year",
  },
}

Feedbin::Application.config.iap_endpoint = {
  production: "https://buy.itunes.apple.com/verifyReceipt",
  sandbox: "https://sandbox.itunes.apple.com/verifyReceipt",
}
