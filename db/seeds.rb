Plan.create!(stripe_id: "basic-monthly", name: "Monthly", price: 2, price_tier: 1)
Plan.create!(stripe_id: "basic-yearly", name: "Yearly", price: 20, price_tier: 1)
Plan.create!(stripe_id: "basic-monthly-2", name: "Monthly", price: 3, price_tier: 2)
Plan.create!(stripe_id: "basic-yearly-2", name: "Yearly", price: 30, price_tier: 2)
Plan.create!(stripe_id: "basic-monthly-3", name: "Monthly", price: 5, price_tier: 3)
Plan.create!(stripe_id: "basic-yearly-3", name: "Yearly", price: 50, price_tier: 3)

Plan.create!(stripe_id: "free", name: "Free", price: 0, price_tier: 3)
Plan.create!(stripe_id: "timed", name: "Timed", price: 0, price_tier: 3)
Plan.create!(stripe_id: "timed", name: "Timed", price: 0, price_tier: 2)
Plan.create!(stripe_id: "app-subscription", name: "App Subscription", price: 0, price_tier: 3)
Plan.create!(stripe_id: "podcast-subscription", name: "Podcast Subscription", price: 0, price_tier: 3)
plan = Plan.create!(stripe_id: "trial", name: "Trial", price: 0, price_tier: 3)

SuggestedCategory.create!(name: "Popular")
SuggestedCategory.create!(name: "Tech")
SuggestedCategory.create!(name: "Design")
SuggestedCategory.create!(name: "Arts & Entertainment")
SuggestedCategory.create!(name: "Sports")
SuggestedCategory.create!(name: "Business")
SuggestedCategory.create!(name: "Food")
SuggestedCategory.create!(name: "News")
SuggestedCategory.create!(name: "Gaming")

if Rails.env.development?
  u = User.new(email: "admin@atalisfunding.com", password: "admin", password_confirmation: "admin", admin: true)
  u.plan = plan
  u.update_auth_token = true
  u.save

  # migration = u.account_migrations.create!(api_token: "asdf")
  # migration.account_migration_items.create!(data: {
  #   title: "Daring Fireball",
  #   feed_id: 290,
  #   feed_url: "http://daringfireball.net/index.xml"
  # })
  # migration.account_migration_items.failed.create!(
  # message: "404 Not Found",
  # data: {
  #   title: "Daring Fireball",
  #   feed_id: 290,
  #   feed_url: "http://daringfireball.net/index.xml"
  # })
  # migration.account_migration_items.complete.create!(
  # message: "Feed imported. Matched 3 of 3 unread articles.",
  # data: {
  #   title: "Daring Fireball",
  #   feed_id: 290,
  #   feed_url: "http://daringfireball.net/index.xml"
  # })

end

u1 = User.new(email: "customer1@atalisfunding.com", password: "admin", password_confirmation: "admin", admin: false)
plan1 = Plan.create!(stripe_id: "trial", name: "Trial", price: 0, price_tier: 3)
u1.plan = plan1
u1.update_auth_token = true
u1.save

Profile.create!(profile_name: "Periodista", created_at: Time.now, updated_at: Time.now)

Tag.create!(name: "La liga", created_at: Time.now, updated_at: Time.now)

RUsersProfile.create!(user_id: 2, profile_id: 1)
RProfilesTag.create!(profile_id: 1, tag_id: 1)

Feed.create!(title: "Mallorca // marca",
  feed_url: "https://e00-marca.uecdn.es/rss/futbol/mallorca.xml",
  site_url: "http://www.marca.com",
  created_at: Time.now,
  updated_at: Time.now,
  subscriptions_count: 1,
  protected: false,
  push_expiration: nil,
  last_published_entry: Time.now,
  host: "www.marca.com",
  self_url: "https://e00-marca.uecdn.es/rss/futbol/mallorca.xml",
  feed_type: "xml",
  active: true,
  options:
   {"description"=>"Mallorca // marca",
    "itunes_categories"=>[],
    "itunes_owners"=>[],
    "image"=>
     {"url"=>"http://estaticos.marca.com/imagen/canalima144.gif",
      "description"=>"marca.com",
      "height"=>"24",
      "link"=>"https://www.marca.com",
      "title"=>"Mallorca // marca",
      "width"=>"144"}}
  )

Entry.create!(
  feed_id: 1,
  title: "Goleada del Mallorca en la segunda prueba de la pretemporada",
  url: "https://www.marca.com/futbol/mallorca/2023/07/17/64b582c422601d3f268b458d.html",
  author: "JUAN MIGUEL SÁNCHEZ",
  summary: "Triunfo 0-9 ante el filial del SV Ried en un choque de muchas probaturas para adquirir ritmo de competición Leer",
  content:
   "Triunfo 0-9 ante el filial del SV Ried en un choque de muchas probaturas para adquirir ritmo de competición&nbsp;<a href=\"https://www.marca.com/futbol/mallorca/2023/07/17/64b582c422601d3f268b458d.html\"> Leer </a><img src=\"http://secure-uk.imrworldwide.com/cgi-bin/m?cid=es-widgetueditorial&amp;cg=rss-marca&amp;ci=es-widgetueditorial&amp;si=https://e00-marca.uecdn.es/rss/futbol/mallorca.xml\" alt=\"\"/>",
  published: Time.now,
  updated: nil,
  created_at: Time.now,
  updated_at: Time.now,
  entry_id: "https://www.marca.com/futbol/mallorca/2023/07/17/64b582c422601d3f268b458d.html",
  public_id: "09ccf11a2b24de0d2b8299aa072006b4fbb31fe8",
  old_public_id: nil,
  starred_entries_count: 0,
  data: {"public_id_alt"=>"14a2c083e51a70f4319a7edac0daedaf061db19b"},
  original: nil,
  source: nil,
  image_url: nil,
  processed_image_url: nil,
  image: nil,
  recently_played_entries_count: 0,
  thread_id: nil,
  settings: {}
)

Subscription.create!(
  user_id: 1,
  feed_id: 1,
  created_at: Time.now,
  updated_at: Time.now,
  title: "RCD Mallorca",
  view_inline: false,
  active: true,
  push: false,
  show_updates: true,
  muted: false,
  show_retweets: true,
  media_only: nil,
  kind: "default",
  view_mode: "article"
)

Tagging.create!(
  feed_id: 1,
  user_id: 1,
  created_at: Time.now,
  updated_at: Time.now,
  tag_id: 1
)


Profile.create!(profile_name: "Biotech")
Profile.create!(profile_name: "Cancer")
Profile.create!(profile_name: "Motor")

Tag.create!(name: "Biomaterials")
Tag.create!(name: "Stem Cell")
Tag.create!(name: "Nanobiotechnology")


Tag.create!(name: "Cancer Advances")
Tag.create!(name: "Prostate Cancer")
Tag.create!(name: "Breast Cancer")

Tag.create!(name: "Formula 1")
Tag.create!(name: "Le Mans")
Tag.create!(name: "GT")

biotech_id = Profile.find_by(profile_name: "Biotech").id

RUsersProfile.create!(user_id: 1, profile_id: biotech_id)

RProfilesTag.create!(profile_id: biotech_id, tag_id: Tag.find_by(name: "Biomaterials").id)
RProfilesTag.create!(profile_id: biotech_id, tag_id: Tag.find_by(name: "Stem Cell").id)
RProfilesTag.create!(profile_id: biotech_id, tag_id: Tag.find_by(name: "Nanobiotechnology").id)


cancer_id = Profile.find_by(profile_name: "Cancer").id

RUsersProfile.create!(user_id: 1, profile_id: cancer_id)

RProfilesTag.create!(profile_id: cancer_id, tag_id: Tag.find_by(name: "Cancer Advances").id)
RProfilesTag.create!(profile_id: cancer_id, tag_id: Tag.find_by(name: "Prostate Cancer").id)
RProfilesTag.create!(profile_id: cancer_id, tag_id: Tag.find_by(name: "Breast Cancer").id)

motor_id = Profile.find_by(profile_name: "Motor").id

RUsersProfile.create!(user_id: 1, profile_id: motor_id)

RProfilesTag.create!(profile_id: motor_id, tag_id: Tag.find_by(name: "Formula 1").id)
RProfilesTag.create!(profile_id: motor_id, tag_id: Tag.find_by(name: "Le Mans").id)
RProfilesTag.create!(profile_id: motor_id, tag_id: Tag.find_by(name: "GT").id)


periodista_id = Profile.find_by(profile_name: "Periodista").id

RUsersProfile.create!(user_id: 1, profile_id: periodista_id)