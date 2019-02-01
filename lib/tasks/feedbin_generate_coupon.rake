require_relative "../../config/boot"
require_relative "../../config/environment"

namespace :feedbin do
  desc "Create a coupon code."
  task :generate_coupon, :sent_to do |t, args|
    include ActionController::Helpers
    if args[:sent_to]
      coupon = Coupon.create!(sent_to: args[:sent_to])
      uri = URI::HTTP.build(
        scheme: Rails.application.config.force_ssl ? "https" : "http",
        host: Rails.application.config.action_mailer.default_url_options[:host],
        path: "/signup",
        query: "coupon_code=#{coupon.coupon_code}"
      )
      puts "----------------------------------------------"
      puts "Coupon id: #{coupon.coupon_code}"
      puts "Coupon URL: #{uri}"
      puts "----------------------------------------------"
    else
      puts "Invalid command, use: rake feedbin:generate_coupon[sent_to]"
      exit 1
    end
    puts args.inspect
  end
end
