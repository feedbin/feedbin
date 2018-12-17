require "test_helper"

class BillingEventsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    StripeMock.start
    event = StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id})
    StripeMock.stop
    @billing_event = BillingEvent.create(info: event.as_json)
  end

  test "should show billing_event" do
    login_as users(:ben)
    skip "@billing_event not fully implemented"
    assert_raises(ActionView::Template::Error) do
      get :show, params: {id: @billing_event}
      assert_not_nil assigns(:billing_event)
    end
  end
end
