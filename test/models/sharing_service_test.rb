require "test_helper"

class SharingServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "active? is always true" do
    assert SharingService.new.active?
  end

  test "ok? is always true" do
    assert SharingService.new.ok?
  end

  test "auth_error? is always false" do
    refute SharingService.new.auth_error?
  end

  test "service_id is 'custom'" do
    assert_equal "custom", SharingService.new.service_id
  end

  test "share_link returns _blank target for http(s) URLs" do
    service = @user.sharing_services.create!(label: "External", url: "https://example.com/share")

    link = service.share_link
    assert_equal "https://example.com/share", link[:url]
    assert_equal "External", link[:label]
    assert_equal "_blank", link[:html_options][:target]
    assert_equal "noopener noreferrer", link[:html_options][:rel]
  end

  test "share_link returns _self target for non-http URLs" do
    service = @user.sharing_services.create!(label: "App link", url: "myapp://share")

    assert_equal "_self", service.share_link[:html_options][:target]
  end

  test "default scope orders by lowercase label" do
    @user.sharing_services.destroy_all
    @user.sharing_services.create!(label: "Zeta", url: "http://z")
    @user.sharing_services.create!(label: "alpha", url: "http://a")
    @user.sharing_services.create!(label: "Mike", url: "http://m")

    labels = @user.sharing_services.reload.map(&:label)
    assert_equal ["alpha", "Mike", "Zeta"], labels
  end
end
