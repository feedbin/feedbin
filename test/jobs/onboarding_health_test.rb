require "test_helper"

class OnboardingHealthTest < ActionMailer::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @original_admin_email = ENV["ADMIN_EMAIL"]
    ENV["ADMIN_EMAIL"] = "admin@example.com"
  end

  teardown do
    ENV["ADMIN_EMAIL"] = @original_admin_email
  end

  test "should not send email when all feeds are healthy" do
    feed = Feed.create_with(
      title: "Daring Fireball",
      site_url: "https://daringfireball.net/",
      crawl_data: {error_count: 3}.stringify_keys
    ).find_or_create_by!(feed_url: "https://daringfireball.net/feeds/main")

    feed.update(crawl_data: {error_count: 3}.stringify_keys)

    assert_emails 0 do
      OnboardingHealth.new.perform
    end
  end

  test "should send email when feeds have high error count" do
    feed = Feed.create_with(
      title: "Daring Fireball",
      site_url: "https://daringfireball.net/",
      crawl_data: {error_count: 10}.stringify_keys
    ).find_or_create_by!(feed_url: "https://daringfireball.net/feeds/main")

    feed.update(crawl_data: {error_count: 10}.stringify_keys)

    assert_emails 1 do
      OnboardingHealth.new.perform
    end
  end

  test "should not send email when ADMIN_EMAIL is not set" do
    ENV["ADMIN_EMAIL"] = nil
    feed = Feed.create_with(
      title: "Daring Fireball",
      site_url: "https://daringfireball.net/",
      crawl_data: {error_count: 10}.stringify_keys
    ).find_or_create_by!(feed_url: "https://daringfireball.net/feeds/main")

    feed.update(crawl_data: {error_count: 10}.stringify_keys)

    assert_emails 0 do
      OnboardingHealth.new.perform
    end
  end

  test "should skip feeds not in database" do
    assert_emails 0 do
      OnboardingHealth.new.perform
    end
  end

  test "should include multiple unhealthy feeds in email" do
    feed1 = Feed.create_with(
      title: "Daring Fireball",
      site_url: "https://daringfireball.net/",
      crawl_data: {error_count: 10}.stringify_keys
    ).find_or_create_by!(feed_url: "https://daringfireball.net/feeds/main")

    feed1.update(crawl_data: {error_count: 10}.stringify_keys)

    feed2 = Feed.create_with(
      title: "Kottke",
      site_url: "http://kottke.org/",
      crawl_data: {error_count: 15}.stringify_keys
    ).find_or_create_by!(feed_url: "http://feeds.kottke.org/main")

    feed2.update(crawl_data: {error_count: 15}.stringify_keys)

    assert_emails 1 do
      OnboardingHealth.new.perform
    end
  end
end
