# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :starred_entry do
    user
    feed
    entry
  end
end
