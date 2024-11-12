require "test_helper"

class Settings::ImportsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get import_export" do
    login_as @user
    get :index
    assert_response :success
  end

  test "should import" do
    login_as @user

    assert_difference -> { ImportItem.count }, +1 do
      assert_difference -> { Tag.count }, +2 do
        assert_difference -> { Import.count }, +1 do
          post :create, params: {
            import: {
              upload: fixture_file_upload("subscriptions.xml", "application/xml")
            }
          }
        end
      end
    end
    assert_redirected_to settings_import_url(Import.last)
    item = ImportItem.last
    assert_equal "Tag One,Tag Two", item.details[:tag]
  end

  test "should show import error" do
    login_as @user

    assert_no_difference -> { Import.count } do
      post :create, params: {
        import: {
          upload: nil
        }
      }
    end

    assert_redirected_to settings_import_export_url
    assert_equal "No file uploaded.", flash[:alert]
  end

  test "should show empty import error" do
    login_as @user

    assert_no_difference -> { Import.count } do
      post :create, params: {
        import: {
          upload: fixture_file_upload("empty.xml", "application/xml")
        }
      }
    end

    assert_redirected_to settings_import_export_url
    assert_equal "No feeds found.", flash[:error].strip
  end
end
