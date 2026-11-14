require "test_helper"

class Api::V3::ApplicationProfileTest < ActiveSupport::TestCase
  setup do
    @application = users(:ben).oauth_applications.create!(name: "My Reader", redirect_uri: "")
    @profile = Api::V3::ApplicationProfile.for(@application)
  end

  test "an application without a profile has an empty one, unsaved" do
    assert @profile.new_record?
    assert_equal @application.id, @profile.application_id
    refute @profile.logo?
  end

  test "keeps a description, a URL and a contact email, without surrounding space" do
    assert @profile.update(description: "  Reads feeds.  ", url: " https://example.com/reader ", contact_email: " dev@example.com ")

    saved = Api::V3::ApplicationProfile.for(@application)
    assert_equal ["Reads feeds.", "https://example.com/reader", "dev@example.com"], saved.values_at(:description, :url, :contact_email)
  end

  test "a field left blank is nothing, not an empty string" do
    assert @profile.update(description: " ", url: "", contact_email: "")

    assert_equal [nil, nil, nil], @profile.reload.values_at(:description, :url, :contact_email)
  end

  test "a URL must be a web address" do
    ["javascript:alert(1)", "ftp://example.com", "example.com", "https://", "http://exa mple.com"].each do |url|
      refute @profile.update(url: url), url
      assert_equal ["URL must start with http:// or https://"], @profile.errors.full_messages, url
    end
  end

  test "a contact email must be an email address" do
    refute @profile.update(contact_email: "not an address")

    assert_equal ["Contact email is not an email address"], @profile.errors.full_messages
  end

  test "a description is at most 500 characters" do
    assert @profile.update(description: "a" * 500)
    refute @profile.update(description: "a" * 501)
  end

  test "stores an uploaded logo as a PNG no larger than 256 pixels" do
    assert @profile.update(logo_file: upload("image.png", "image/png"))

    image = Vips::Image.new_from_buffer(@profile.reload.logo, "")
    assert_equal :png, ImageFormat.new(@profile.logo).format
    assert_equal 256, [image.width, image.height].max
    assert @profile.logo?
  end

  test "converts other formats to PNG" do
    @profile.update!(logo_file: upload("image.jpeg", "image/jpeg"))

    assert_equal :png, ImageFormat.new(@profile.reload.logo).format
  end

  test "refuses a logo that is not a plain raster image, whatever it claims to be, and saves nothing" do
    %w[atom.xml favicon.ico].each do |file|
      refute @profile.update(description: "Reads feeds.", logo_file: upload(file, "image/png")), file
      assert_equal ["Logo must be a PNG, JPEG, GIF or WebP image under 5 MB"], @profile.errors.full_messages
    end

    assert_equal 0, Api::V3::ApplicationProfile.count
  end

  test "a refused logo leaves the one already there" do
    @profile.update!(logo_file: upload("image.png", "image/png"))
    stored = @profile.reload.logo

    refute @profile.update(logo_file: upload("atom.xml", "image/png"))

    assert_equal stored, Api::V3::ApplicationProfile.for(@application).logo
  end

  test "a new logo replaces the old one and moves its version" do
    @profile.update!(logo_file: upload("image.png", "image/png"))
    first = @profile.logo_updated_at

    travel 1.minute do
      @profile.update!(logo_file: upload("image.jpeg", "image/jpeg"))
    end

    assert_equal 1, Api::V3::ApplicationProfile.where(application_id: @application.id).count
    assert_operator @profile.logo_updated_at, :>, first
  end

  test "editing the details leaves the logo's version alone" do
    @profile.update!(logo_file: upload("image.png", "image/png"))
    version = @profile.logo_updated_at

    travel(1.minute) { @profile.update!(description: "Reads feeds.") }

    assert_equal version, @profile.reload.logo_updated_at
  end

  test "removing the logo keeps the details" do
    @profile.update!(description: "Reads feeds.", logo_file: upload("image.png", "image/png"))

    @profile.remove_logo

    saved = Api::V3::ApplicationProfile.for(@application)
    refute saved.logo?
    assert_nil saved.logo
    assert_equal "Reads feeds.", saved.description
  end

  test "can be read without the logo's bytes" do
    @profile.update!(description: "Reads feeds.", logo_file: upload("image.png", "image/png"))

    listed = Api::V3::ApplicationProfile.without_logo.for(@application)

    assert listed.logo?
    assert_equal "Reads feeds.", listed.description
    refute listed.has_attribute?(:logo)
  end

  test "is deleted with its application" do
    @profile.update!(logo_file: upload("image.png", "image/png"))

    @application.destroy

    assert_equal 0, Api::V3::ApplicationProfile.count
  end

  private

  def upload(name, type)
    Rack::Test::UploadedFile.new(support_file(name), type)
  end
end
