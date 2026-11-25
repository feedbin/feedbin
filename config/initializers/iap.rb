Feedbin::Application.config.iap = {
  "com.feedbin.feedbin.one_month" => {
    time: 31.days,
    amount: 399,
    name: "One Month"
  },
  "com.feedbin.feedbin.six_months" => {
    time: 183.days,
    amount: 1999,
    name: "Six Months"
  },
  "com.feedbin.feedbin.one_year" => {
    time: 365.days,
    amount: 3999,
    name: "One Year"
  }
}

Feedbin::Application.config.iap_endpoint = {
  production: "https://buy.itunes.apple.com/verifyReceipt",
  sandbox: "https://sandbox.itunes.apple.com/verifyReceipt"
}

# The apps whose subscriptions an account may present. A notification says
# which one it is for; Apple's API is asked as that app.
Feedbin::Application.config.app_store_bundle_ids = ENV.fetch(
  "APPLE_STORE_BUNDLE_IDS",
  "com.feedbin.feedbin.app,com.feedbininc.Feedbin,com.feedbininc.FeedbinReflex,com.feedbin.Podcast"
).split(",").map(&:strip)
