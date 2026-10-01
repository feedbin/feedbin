namespace :feedbin do
  desc "See what is deployed."
  task :deploy_diff do
    response = HTTP.timeout(write: 5, connect: 5, read: 20).get("https://feedbin.com/version")
    current_version = response.to_s.chomp
    path = "/feedbin/feedbin/compare/%s...main" % current_version
    uri = URI::HTTP.build(
      scheme: "https",
      host: "github.com",
      path: path
    )
    `open #{uri}`
  end
end
