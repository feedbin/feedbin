require "test_helper"

class Api::V2::ImportsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
  end

  test "should create import" do
    login_as @user

    xml = <<-eot
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
        <body>
          <outline text="Hypercritical" title="Hypercritical" type="rss" xmlUrl="http://hypercritical.co/feeds/main" htmlUrl="http://hypercritical.co/"/>
        </body>
      </opml>
    eot

    assert_difference "Import.count", +1 do
      post :create, body: xml, format: :json
      assert_response :success
    end
  end

  test "should get imports" do
    login_as @user
    @user.imports.create!
    get :index, format: :json
    imports = parse_json
    assert_equal(1, imports.length)
    assert_response :success
  end

  test "should get import" do
    login_as @user
    import = @user.imports.create!
    get :show, params: {id: import}, format: :json
    import = parse_json
    assert_response :success
  end

end

