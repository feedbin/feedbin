require "test_helper"

class RemoteFilesControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    flush_redis
  end

  test "should be unauthorized without pull key" do
    get :icon, params: {signature: "asdf", url: "asdf"}
    assert_response :not_found
  end

  test "should be unauthorized without valid signature" do
    authorize
    get :icon, params: {signature: "asdf", url: "asdf"}
    assert_response :not_found
  end

  test "should be unauthorized without http url" do
    authorize
    url = "example.com/image.jpeg"
    signature, encoded_url = RemoteFile.signed_url(url).split("/").last(2)
    get :icon, params: {signature: signature, url: encoded_url}
    assert_response :not_found
  end

  test "should be redirect without icon bucket" do
    RemoteFile.stub_const(:BUCKET, nil) do
      authorize
      url = "http://example.com/image.jpeg"
      signature, encoded_url = RemoteFile.signed_url(url).split("/").last(2)
      get :icon, params: {signature: signature, url: encoded_url}
      assert_redirected_to url
    end
  end

  test "should get proxy redirect" do
    authorize
    url = "http://example.com/image.jpeg"
    signature, encoded_url = RemoteFile.signed_url(url).split("/").last(2)

    # Deploy A: the proxy serves a miss through camo and caches nothing; the copy backfill and the crawlers write the rows now.
    assert_no_difference -> { ImageCrawler::Pipeline::Find.jobs.size } do
      get :icon, params: {signature: signature, url: encoded_url}
      assert_response :success
    end

    assert_equal "#{ENV["CAMO_HOST"]}/#{signature}/#{encoded_url}", response.header[RemoteFilesController::URL_HEADER]
    assert_equal "400", response.header[RemoteFilesController::SIZE_HEADER]
    assert_equal "example.com", response.header[RemoteFilesController::HOST_HEADER]
    assert response.header[RemoteFilesController::SENDFILE_HEADER].start_with?(RemoteFilesController::PROXY_PATH)
  end

  test "should get storage redirect" do
    authorize
    url = "http://example.com/image.jpeg"
    storage_url = "http://aws.amazonaws.com/asdf/asdfasf"
    icon = RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: storage_url)

    signature, encoded_url = RemoteFile.signed_url(url).split("/").last(2)

    get :icon, params: {signature: signature, url: encoded_url}
    assert_response :success

    assert_equal storage_url, response.header[RemoteFilesController::URL_HEADER]
    assert_equal "400", response.header[RemoteFilesController::SIZE_HEADER]
    assert_equal "aws.amazonaws.com", response.header[RemoteFilesController::HOST_HEADER]
    assert response.header[RemoteFilesController::SENDFILE_HEADER].start_with?(RemoteFilesController::PROXY_PATH)
  end

  # Deploy A: a miss creates no legacy row and schedules no crawl; the copy
  # backfill and the avatar crawlers write the rows now.
  test "should create an icon" do
    authorize
    image_url = "http://example.com/image.jpg"
    camo_url = RemoteFile.camo_url(image_url)
    signature, encoded_url = RemoteFile.signed_url(image_url).split("/").last(2)

    assert_no_difference "RemoteFile.count" do
      get :icon, params: {signature: signature, url: encoded_url}
      assert_response :success
    end

    assert_equal camo_url, response.header[RemoteFilesController::URL_HEADER]
  end

  private

  def authorize
    @request.headers[RemoteFilesController::AUTH_HEADER] = RemoteFilesController::AUTH_KEY
  end
end
