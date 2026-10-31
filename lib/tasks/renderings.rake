namespace :renderings do
  desc "Record ContentFormatter::VERSION and its fingerprint for the test suite"
  task fingerprint: :environment do
    path = Rails.root.join("test/fixtures/files/content_formatter_fingerprint.txt")
    File.write(path, "#{ContentFormatter::VERSION} #{ContentFormatter.fingerprint}\n")
    puts File.read(path)
  end
end
