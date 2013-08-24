FactoryGirl.define do

  factory :user do
    sequence(:email) {|n| "person#{n}@example.com" }
    password "passw0rd"
    admin    true
  end

  factory :feed do
    title 'Ben Ubois'
    sequence(:feed_url) {|n| "http://benubois#{n}.com/atom.xml" }
    site_url 'http://benubois.com'
    etag 'er3223423423422342'
    last_modified { Time.now }
  end
  
  factory :entry do
    association :feed
    title 'Title'
    url 'http://benubois.com/post'
    author 'Ben'
    content '<p>Content</p>'
    sequence(:public_id) {|n| "3234234234231ae#{n}" }
    published { Time.now }
    updated  { Time.now }
  end
  
  factory :subscription do
    association :user
    association :feed
  end
  
end
