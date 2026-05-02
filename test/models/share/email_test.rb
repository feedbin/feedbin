require "test_helper"

class Share::EmailTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = @user.feeds.first
    @entry = @feed.entries.create!(content: "<p>x</p>", title: "T", url: "/p/1", public_id: SecureRandom.hex)
    @klass = @user.supported_sharing_services.create!(service_id: "email")
  end

  test "share enqueues an EntryMailer with reply_to defaulting to the user's email" do
    Sidekiq::Worker.clear_all
    enqueued = []
    EntryMailer.stub :mailer, ->(*args) {
      enqueued << args
      OpenStruct.new(deliver_later: true)
    } do
      result = Share::Email.new(@klass).share(
        entry_id: @entry.id,
        to: "alice@example.com",
        subject: "Hi",
        body: "Body",
        readability: nil
      )
      assert_equal({message: "Email sent to alice@example.com."}, result)
    end
    args = enqueued.first
    assert_equal @user.email, args[5] # from_name fallback
    assert_equal @user.email, args[4] # reply_to fallback
  end

  test "share uses email_address and email_name when set on the klass" do
    @klass.update!(email_address: "from@example.com", email_name: "Sender")
    enqueued = []
    EntryMailer.stub :mailer, ->(*args) {
      enqueued << args
      OpenStruct.new(deliver_later: true)
    } do
      Share::Email.new(@klass).share(entry_id: @entry.id, to: "x@example.com")
    end
    args = enqueued.first
    assert_equal "from@example.com", args[4]
    assert_equal "Sender", args[5]
  end

  test "share splits the recipient list and forwards to update_completions" do
    captured = nil
    @klass.define_singleton_method(:update_completions) { |list| captured = list; nil }
    EntryMailer.stub :mailer, ->(*) { OpenStruct.new(deliver_later: true) } do
      Share::Email.new(@klass).share(entry_id: @entry.id, to: " a@x.com , b@y.com ")
    end
    assert_equal ["a@x.com", "b@y.com"], captured
  end
end
