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
    assert_equal ["Tag One", "Tag Two"], item.details[:tag]
  end

  test "should show a report whose OPML outlines had text but no title" do
    login_as @user

    import = @user.imports.new(filename: "subscriptions.opml")
    import.import_items.new(status: :failed, details: {
      title: "Has a title", text: "Has a title",
      xml_url: "http://a.example.com/feed.xml", html_url: "http://a.example.com/"
    })
    # text is the required OPML attribute; title is optional.
    import.import_items.new(status: :failed, details: {
      text: "Only text",
      xml_url: "http://b.example.com/feed.xml", html_url: "http://b.example.com/"
    })
    import.save!
    import.update_column(:complete, true)

    get :show, params: {id: import.id}

    assert_response :success
    assert_includes @response.body, "Only text"
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
