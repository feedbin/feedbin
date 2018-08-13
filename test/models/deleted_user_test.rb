require "test_helper"

class DeletedUserTest < ActiveSupport::TestCase
  setup do
    @deleted_user = DeletedUser.create(email: "example@example.com", customer_id: "cus_123")
  end

  test "should search" do
    assert_equal(1, DeletedUser.search("example").length)
  end

  test "should get stripe url" do
    assert_not_nil(@deleted_user.stripe_url)
  end

  test "should get deleted?" do
    assert @deleted_user.deleted?
  end
end
