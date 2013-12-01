Plan.create!(stripe_id: 'basic-monthly', name: "Monthly", price: 2, price_tier: 1)
Plan.create!(stripe_id: 'basic-yearly', name: "Yearly", price: 20, price_tier: 1)
Plan.create!(stripe_id: 'basic-monthly-2', name: "Monthly", price: 3, price_tier: 2)
Plan.create!(stripe_id: 'basic-yearly-2', name: "Yearly", price: 30, price_tier: 2)
Plan.create!(stripe_id: 'free', name: "Free", price: 0, price_tier: 2)
plan = Plan.create!(stripe_id: 'trial', name: "Trial", price: 0, price_tier: 2)


u = User.new(email: "ben@benubois.com", password: 'passw0rd', password_confirmation: 'passw0rd', admin: true)
u.plan = plan
u.update_auth_token = true
u.save
