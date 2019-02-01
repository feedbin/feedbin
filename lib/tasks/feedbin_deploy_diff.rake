namespace :feedbin  do
  desc "See what is deployed."
  task :deploy_diff do
    response = HTTParty.get("https://feedbin.com/version", {timeout: 20})
    current_version = response.parsed_response.chomp
    path = "/feedbin/feedbin/compare/%s...master" % current_version
    uri = URI::HTTP.build(
      scheme: "https",
      host: "github.com",
      path: path
    )
    `open #{uri.to_s}`
  end
end
