require "test_helper"

class SupportedSharingServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "validates that service_id is one of the SERVICES list" do
    record = @user.supported_sharing_services.new(service_id: "not-a-real-service")
    refute record.valid?
    assert_includes record.errors[:service_id], "is not included in the list"
  end

  test "service_id must be unique per user" do
    @user.supported_sharing_services.create!(service_id: "instapaper")
    duplicate = @user.supported_sharing_services.new(service_id: "instapaper")
    refute duplicate.valid?
    assert_includes duplicate.errors[:service_id], "has already been taken"
  end

  test "info returns the service definition for a known service_id" do
    info = SupportedSharingService.info("instapaper")
    assert_equal "Instapaper", info.label
    assert_equal "xauth", info.service_type
  end

  test "info returns nil for an unknown service_id" do
    assert_nil SupportedSharingService.info("not-real")
  end

  test "info! raises ActionController::RoutingError for an unknown service_id" do
    assert_raises(ActionController::RoutingError) do
      SupportedSharingService.info!("not-real")
    end
  end

  test "label, service_type, klass, requires_auth? read from the service info" do
    record = @user.supported_sharing_services.create!(service_id: "instapaper")
    assert_equal "Instapaper", record.label
    assert_equal "xauth", record.service_type
    assert_equal "Share::Instapaper", record.klass
    assert record.requires_auth?
  end

  test "html_options falls back to data-remote when not configured" do
    record = @user.supported_sharing_services.create!(service_id: "instapaper")
    assert_equal({"data-remote" => true}, record.html_options)
  end

  test "html_options returns the configured options when present" do
    record = @user.supported_sharing_services.create!(service_id: "email")
    assert_equal "show_entry_basement", record.html_options["data-behavior"]
  end

  test "active? defaults to true when the service has no active flag" do
    record = @user.supported_sharing_services.create!(service_id: "instapaper")
    assert record.active?
  end

  test "active? respects the configured active flag" do
    record = @user.supported_sharing_services.create!(service_id: "pocket")
    refute record.active?
  end

  test "has_share_sheet? reflects whether the configuration declares one" do
    with_sheet = @user.supported_sharing_services.create!(service_id: "email")
    without_sheet = @user.supported_sharing_services.create!(service_id: "instapaper")
    assert with_sheet.has_share_sheet?
    refute without_sheet.has_share_sheet?
  end

  test "auth_present? reflects whether an access token is stored" do
    record = @user.supported_sharing_services.create!(service_id: "instapaper")
    refute record.auth_present?

    record.update!(access_token: "tok")
    assert record.auth_present?
  end

  test "remove_access! clears the access token and secret" do
    record = @user.supported_sharing_services.create!(service_id: "instapaper", access_token: "tok", access_secret: "sec")

    record.remove_access!

    assert_nil record.reload.access_token
    assert_nil record.access_secret
  end

  test "completions returns the saved completions or an empty array" do
    record = @user.supported_sharing_services.create!(service_id: "email")
    assert_equal [], record.completions

    record.update!(service_options: {"completions" => ["a@example.com"]})
    assert_equal ["a@example.com"], record.completions
  end

  test "update_completions appends and de-duplicates entries" do
    record = @user.supported_sharing_services.create!(service_id: "email", service_options: {"completions" => ["a@example.com"]})

    record.update_completions(["a@example.com", "b@example.com"])

    assert_equal Set.new(["a@example.com", "b@example.com"]), Set.new(record.reload.completions)
  end

  test "limit_exceeded returns an error response" do
    record = @user.supported_sharing_services.create!(service_id: "email")
    assert_equal({error: "Share limit exceeded"}, record.limit_exceeded)
  end
end
