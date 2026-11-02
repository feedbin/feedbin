namespace :api_v3 do
  desc "Mark an OAuth application as Feedbin's own: its tokens get the account scope"
  task :first_party, [:uid] => :environment do |_task, args|
    application = Doorkeeper::Application.find_by!(uid: args.fetch(:uid))
    application.update!(scopes: Api::V3::Scopes::FIRST_PARTY)
    tokens = application.access_tokens.where(revoked_at: nil).update_all(scopes: Api::V3::Scopes::FIRST_PARTY)
    puts "#{application.name}: scopes #{application.scopes}; #{tokens} tokens upgraded"
  end
end
