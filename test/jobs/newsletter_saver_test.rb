require "test_helper"

class NewsletterSaverTest < ActiveSupport::TestCase
  B2 = %r{test-account\.storage\.example\.com/newsletters-test/}

  setup do
    Sidekiq::Worker.clear_all
    @entry = create_entry(Feed.first)
  end

  test "Saves to B2 with the gzip headers" do
    request = stub_request(:put, B2)
      .with(headers: {
        "Content-Encoding" => "gzip",
        "Content-Type" => "text/html; charset=utf-8",
        "Cache-Control" => "max-age=315360000, public"
      })
      .with { |req| ActiveSupport::Gzip.decompress(req.body).include?("<title>#{@entry.title}</title>") }

    NewsletterSaver.new.perform(@entry.id)

    assert_requested request, times: 1
    assert_not_requested :put, /s3\.amazonaws\.com/
  end

  test "B2 put carries no x-amz acl or storage class" do
    request = stub_request(:put, B2).with { |req| req.headers.keys.grep(/\AX-Amz-(Acl|Storage-Class)\z/).empty? }

    NewsletterSaver.new.perform(@entry.id)

    assert_requested request
  end

  test "Also writes to S3 while the legacy bucket is set" do
    b2 = stub_request(:put, B2)
    s3 = stub_request(:put, /s3\.amazonaws\.com/)
      .with(headers: {
        "Content-Encoding" => "gzip",
        "X-Amz-Acl" => "public-read",
        "X-Amz-Storage-Class" => "REDUCED_REDUNDANCY"
      })
      .with { |req| ActiveSupport::Gzip.decompress(req.body).include?(@entry.content) }

    with_env("AWS_S3_BUCKET_NEWSLETTERS" => "legacy-newsletters") do
      NewsletterSaver.new.perform(@entry.id)
    end

    assert_requested b2
    assert_requested s3
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

  test "Does not write the entry when the url is current" do
    stub_request(:put, B2)

    with_env("NEWSLETTER_HOST" => "newsletters.example.com") do
      NewsletterSaver.new.perform(@entry.id)
      updated = @entry.reload.updated_at
      NewsletterSaver.new.perform(@entry.id)
      assert_equal updated, @entry.reload.updated_at
    end
  end

  test "A B2 failure leaves the S3 copy written" do
    stub_request(:put, B2).to_return(status: 500)
    s3 = stub_request(:put, /s3\.amazonaws\.com/)

    with_env("AWS_S3_BUCKET_NEWSLETTERS" => "legacy-newsletters") do
      assert_raises(Excon::Error) { NewsletterSaver.new.perform(@entry.id) }
    end

    assert_requested s3
  end
end
