require "test_helper"

class ShareRetryTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @service = @user.supported_sharing_services.create!(service_id: "instapaper")
  end

  test "swallows ActiveRecord::RecordNotFound when the sharing service is missing" do
    assert_nothing_raised do
      ShareRetry.new.perform(0, {entry_id: 1})
    end
  end

  test "raises when the service add returns a non-200 status" do
    @service.stub :service, fake_service_returning(500) do
      SupportedSharingService.stub :find, ->(_) { @service } do
        assert_raises(RuntimeError) do
          ShareRetry.new.perform(@service.id, {entry_id: 1})
        end
      end
    end
  end

  test "succeeds quietly when the service add returns 200" do
    @service.stub :service, fake_service_returning(200) do
      SupportedSharingService.stub :find, ->(_) { @service } do
        assert_nothing_raised do
          ShareRetry.new.perform(@service.id, {entry_id: 1})
        end
      end
    end
  end

  private

  def fake_service_returning(code)
    fake = Object.new
    fake.define_singleton_method(:add) { |_| code }
    fake
  end
end
