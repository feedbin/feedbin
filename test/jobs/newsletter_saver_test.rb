require "test_helper"

class NewsletterSaverTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  test "Saves to storage" do
    entry = create_entry(Feed.first)
    document = "<html><head><title>#{entry.title}</title></head><body>#{entry.content}</body></html>"
    stub_request(:put, /s3\.amazonaws\.com/)
      .with(headers: {
        "Content-Encoding"    => "gzip",
        "Content-Type"        => "text/html; charset=utf-8",
        "X-Amz-Acl"           => "public-read",
        "X-Amz-Storage-Class" => "REDUCED_REDUNDANCY"
      })
      .with { |request| document == ActiveSupport::Gzip.decompress(request.body)}

    saver = NewsletterSaver.new.perform(entry.id)
  end

  test "Saves text email to storage" do
    entry = create_entry(Feed.first)
    entry.update(data: {format: "text"})
    document = "<title>#{entry.title}</title>"
    stub_request(:put, /s3\.amazonaws\.com/)
      .with { |request| ActiveSupport::Gzip.decompress(request.body).include?(document) }

    saver = NewsletterSaver.new.perform(entry.id)
  end
end
