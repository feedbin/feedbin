require "test_helper"

class NewsletterSaverTest < ActiveSupport::TestCase
  B2 = %r{test-account\.storage\.example\.com/newsletters-test/}

  setup do
    Sidekiq::Worker.clear_all
    @entry = create_entry(Feed.first)
  end

  test "Saves to B2 only, without S3 headers, even with the old S3 bucket set" do
    request = stub_request(:put, B2).with { |req| req.headers.keys.grep(/\AX-Amz-(Acl|Storage-Class)\z/).empty? }

    with_env("AWS_S3_BUCKET_NEWSLETTERS" => "legacy-newsletters") do
      NewsletterSaver.new.perform(@entry.id)
    end

    assert_requested request, times: 1
    assert_not_requested :put, /s3\.amazonaws\.com/
  end

  test "Sets entry url from the host and key" do
    stub_request(:put, B2)

    with_env("NEWSLETTER_HOST" => "newsletters.example.com") do
      NewsletterSaver.new.perform(@entry.id)
    end

    assert_equal "https://newsletters.example.com/#{@entry.public_id[0..2]}/#{@entry.public_id}.html", @entry.reload.url
  end

  test "Leaves entry url alone without a host" do
    stub_request(:put, B2)
    url = @entry.url

    with_env("NEWSLETTER_HOST" => nil) do
      NewsletterSaver.new.perform(@entry.id)
    end

    assert_equal url, @entry.reload.url
  end
end
