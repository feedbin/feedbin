require "test_helper"

class ApplicationMailerTest < ActiveSupport::TestCase
  class RejectingDelivery
    class_attribute :exception
    class_attribute :attempts, default: 0

    def initialize(settings = {})
    end

    def deliver!(mail)
      self.class.attempts += 1
      raise self.class.exception
    end
  end

  class RejectedMailer < ApplicationMailer
    def notice
      mail(to: "someone@example.com", from: "test@example.com", subject: "Notice", body: "Notice")
    end
  end

  setup do
    ActionMailer::Base.add_delivery_method :rejecting, RejectingDelivery
    RejectedMailer.delivery_method = :rejecting
    RejectingDelivery.attempts = 0
  end

  teardown do
    RejectedMailer.delivery_method = :test
  end

  # Mail goes out with deliver_later, so what matters is whether the delivery
  # job survives the failure. Drive that job directly: deliver_later itself
  # only pushes to Sidekiq.
  def deliver_later_now
    ActionMailer::MailDeliveryJob.perform_now(RejectedMailer.name, "notice", "deliver_now", args: [])
  end

  test "a rejection the provider will never accept is discarded rather than retried" do
    RejectingDelivery.exception = Postmark::InactiveRecipientError.new("recipient is inactive")

    deliver_later_now

    assert_equal 1, RejectingDelivery.attempts, "the delivery should be attempted once and then given up on"
  end

  test "a transient provider failure is left to retry" do
    RejectingDelivery.exception = Postmark::InternalServerError.new(500, "server error")

    assert_raises Postmark::InternalServerError do
      deliver_later_now
    end
  end
end
