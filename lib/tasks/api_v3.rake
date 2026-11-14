namespace :api_v3 do
  desc "Mark an OAuth application as Feedbin's own: its tokens get the account scope"
  task :first_party, [:uid] => :environment do |_task, args|
    puts Api::V3::Scopes.first_party!(args.fetch(:uid))
  end
end
