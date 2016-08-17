require 'test_helper'

class MigrateBillingEventTest < ActiveSupport::TestCase

  test "should schedule work" do
    Sidekiq::Worker.clear_all
    expected_ids = BillingEvent.all.pluck(:id).sort
    assert_difference "MigrateBillingEvent.jobs.size", +expected_ids.length do
      MigrateBillingEvent.new().perform(nil, true)
    end
    actual_ids = MigrateBillingEvent.jobs.collect_concat { |job| job["args"] }.sort
    assert_equal expected_ids, actual_ids
  end

  test "should migrate info" do
    BillingEvent.all.each do |billing_event|
      assert_no_difference "MigrateBillingEvent.jobs.size" do
        MigrateBillingEvent.new().perform(billing_event.id)
        assert billing_event.reload.info.present?
        assert_equal billing_event.reload.info, billing_event.details.as_json
      end
    end
  end

end
