# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :user do
    email { Faker::Internet.email }
    password { Faker::Internet.password(8) }
    password_confirmation { |u| u.password }
    plan { Plan.find_by_stripe_id('trial') }
    update_auth_token { true }
  end
end
