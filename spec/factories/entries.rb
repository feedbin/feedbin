# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :entry do
    sequence(:public_id) { |n| "#{n}123#{n+5}"}
  end
end
