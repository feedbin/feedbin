require "test_helper"

class Api::V3::ApplicationLogoTest < ActiveSupport::TestCase
  setup do
    @application = users(:ben).oauth_applications.create!(name: "My Reader", redirect_uri: "")
  end

  test "stores an upload as a PNG no larger than 256 pixels" do
    logo = Api::V3::ApplicationLogo.replace(@application, upload("image.png", "image/png"))

    image = Vips::Image.new_from_buffer(logo.data, "")
    assert_equal :png, ImageFormat.new(logo.data).format
    assert_equal 256, [image.width, image.height].max
  end

  test "converts other formats to PNG" do
    logo = Api::V3::ApplicationLogo.replace(@application, upload("image.jpeg", "image/jpeg"))

    assert_equal :png, ImageFormat.new(logo.data).format
  end

  test "refuses a file that is not an image, whatever it claims to be" do
    assert_nil Api::V3::ApplicationLogo.replace(@application, upload("atom.xml", "image/png"))
    assert_nil Api::V3::ApplicationLogo.for(@application)
  end

  test "refuses formats that are not plain raster images" do
    assert_nil Api::V3::ApplicationLogo.replace(@application, upload("favicon.ico", "image/png"))
  end

  test "a new upload replaces the old one" do
    Api::V3::ApplicationLogo.replace(@application, upload("image.png", "image/png"))
    Api::V3::ApplicationLogo.replace(@application, upload("image.jpeg", "image/jpeg"))

    assert_equal 1, Api::V3::ApplicationLogo.where(application_id: @application.id).count
  end

  test "is deleted with its application" do
    Api::V3::ApplicationLogo.replace(@application, upload("image.png", "image/png"))

    @application.destroy

    assert_equal 0, Api::V3::ApplicationLogo.count
  end

  private

  def upload(name, type)
    Rack::Test::UploadedFile.new(support_file(name), type)
  end
end
