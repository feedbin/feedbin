require "test_helper"

class Api::V3::ApplicationProfileTest < ActiveSupport::TestCase
  STORED = %r{\Ahttps://test-account\.storage\.example\.com/images-test/(\h{3}/\h{32}\.png)\z}

  setup do
    @application = users(:ben).oauth_applications.create!(name: "My Reader", redirect_uri: "")
    @profile = Api::V3::ApplicationProfile.for(@application)
  end

  test "an application without a profile has an empty one, unsaved" do
    assert @profile.new_record?
    assert_equal @application.id, @profile.application_id
    refute @profile.logo?
    assert_nil @profile.logo_url
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

  test "puts an uploaded logo in the image store as a PNG no larger than 256 pixels, cached for good" do
    with_image_store do
      assert @profile.update(logo_file: upload("image.png", "image/png"))

      assert_requested(:put, STORED, times: 1) do |request|
        image = Vips::Image.new_from_buffer(request.body, "")
        @stored_path = request.uri.path.delete_prefix("/images-test/")
        request.headers["Content-Type"] == "image/png" &&
          request.headers["Cache-Control"].include?("immutable") &&
          ImageFormat.new(request.body).format == :png &&
          [image.width, image.height].max == 256
      end
      assert_equal @stored_path, @profile.reload.logo_storage_path
      assert @profile.logo?
      assert_equal "https://images.example.com/#{@stored_path}", @profile.logo_url
    end
  end

  test "converts other formats to PNG" do
    with_image_store do
      @profile.update!(logo_file: upload("image.jpeg", "image/jpeg"))

      assert_requested(:put, STORED) { ImageFormat.new(it.body).format == :png }
    end
  end

  test "refuses a logo that is not a plain raster image, whatever it claims to be, and stores nothing" do
    with_image_store do
      %w[atom.xml favicon.ico].each do |file|
        refute @profile.update(description: "Reads feeds.", logo_file: upload(file, "image/png")), file
        assert_equal ["Logo must be a PNG, JPEG, GIF or WebP image under 5 MB"], @profile.errors.full_messages
      end

      assert_not_requested :put, STORED
      assert_equal 0, Api::V3::ApplicationProfile.count
    end
  end

  test "a refused logo leaves the one already there" do
    with_image_store do
      @profile.update!(logo_file: upload("image.png", "image/png"))
      stored = @profile.logo_storage_path

      assert_no_difference -> { SweepStoredImages.jobs.size } do
        refute @profile.update(logo_file: upload("atom.xml", "image/png"))
      end

      assert_equal stored, Api::V3::ApplicationProfile.for(@application).logo_storage_path
    end
  end

  test "a new logo gets a path of its own, even for the same image, and the old object is deleted" do
    with_image_store do
      @profile.update!(logo_file: upload("image.png", "image/png"))
      first = @profile.logo_storage_path

      assert_difference -> { SweepStoredImages.jobs.size }, +1 do
        @profile.update!(logo_file: upload("image.png", "image/png"))
      end

      refute_equal first, @profile.logo_storage_path
      assert_equal [[first]], SweepStoredImages.jobs.last["args"]
      assert_equal 1, Api::V3::ApplicationProfile.where(application_id: @application.id).count
    end
  end

  test "editing the details leaves the logo alone" do
    with_image_store do
      @profile.update!(logo_file: upload("image.png", "image/png"))
      stored = @profile.logo_storage_path

      assert_no_difference -> { SweepStoredImages.jobs.size } do
        @profile.update!(description: "Reads feeds.")
      end

      assert_equal stored, @profile.reload.logo_storage_path
      assert_requested :put, STORED, times: 1
    end
  end

  test "removing the logo keeps the details and deletes the object" do
    with_image_store do
      @profile.update!(description: "Reads feeds.", logo_file: upload("image.png", "image/png"))
      stored = @profile.logo_storage_path

      assert_difference -> { SweepStoredImages.jobs.size }, +1 do
        @profile.remove_logo
      end

      saved = Api::V3::ApplicationProfile.for(@application)
      refute saved.logo?
      assert_equal "Reads feeds.", saved.description
      assert_equal [[stored]], SweepStoredImages.jobs.last["args"]
    end
  end

  test "a logo the store does not take saves nothing and says so" do
    with_image_store do
      stub_request(:put, STORED).to_return(status: 503)

      refute @profile.update(description: "Reads feeds.", logo_file: upload("image.png", "image/png"))

      assert_equal ["Logo could not be stored. Try again"], @profile.errors.full_messages
      assert_equal 0, Api::V3::ApplicationProfile.count
    end
  end

  test "without an image store a logo is refused, and the details can still be saved" do
    with_env("UNIFIED_BUCKET_IMAGES" => nil) do
      refute @profile.update(logo_file: upload("image.png", "image/png"))
      assert_equal ["Logo could not be stored. Try again"], @profile.errors.full_messages

      assert Api::V3::ApplicationProfile.for(@application).update(description: "Reads feeds.")
    end
  end

  test "is deleted with its application" do
    @profile.update!(description: "Reads feeds.")

    @application.destroy

    assert_equal 0, Api::V3::ApplicationProfile.count
  end

  test "destroying a profile deletes its logo's object" do
    with_image_store do
      @profile.update!(logo_file: upload("image.png", "image/png"))
      stored = @profile.logo_storage_path

      @profile.destroy

      assert_equal [[stored]], SweepStoredImages.jobs.last["args"]
    end
  end

  test "deleting an account deletes the logos of its applications" do
    with_image_store do
      @profile.update!(logo_file: upload("image.png", "image/png"))
      stored = @profile.logo_storage_path
      StripeMock.start

      users(:ben).destroy

      assert_equal [[stored]], SweepStoredImages.jobs.last["args"]
      assert_equal 0, Api::V3::ApplicationProfile.count
    end
  end

  private

  def upload(name, type)
    Rack::Test::UploadedFile.new(support_file(name), type)
  end
end
