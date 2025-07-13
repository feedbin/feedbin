require "test_helper"
require "zlib"
require "stringio"

class CompressedRequestTest < ActiveSupport::TestCase
  def setup
    @app = lambda { |env| [200, {}, ["OK"]] }
    @middleware = CompressedRequest.new(@app)
  end

  test "passes through non-extension requests unchanged" do
    env = {
      "REQUEST_PATH" => "/api/v2/entries",
      "rack.input" => StringIO.new("test body")
    }

    status, headers, body = @middleware.call(env)

    assert_equal 200, status
    env["rack.input"].rewind
    assert_equal "test body", env["rack.input"].read
  end

  test "passes through extension requests without gzip encoding unchanged" do
    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "rack.input" => StringIO.new("test body")
    }

    status, headers, body = @middleware.call(env)

    assert_equal 200, status
    env["rack.input"].rewind
    assert_equal "test body", env["rack.input"].read
  end

  test "decompresses gzipped extension requests" do
    original_body = "This is the original request body"
    compressed_body = StringIO.new
    Zlib::GzipWriter.wrap(compressed_body) { |gz| gz.write(original_body) }

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "gzip",
      "rack.input" => StringIO.new(compressed_body.string),
      "CONTENT_LENGTH" => compressed_body.string.bytesize.to_s
    }

    status, headers, body = @middleware.call(env)

    assert_equal 200, status
    assert_equal original_body, env["rack.input"].read
    assert_equal original_body.bytesize.to_s, env["CONTENT_LENGTH"]
    assert_nil env["HTTP_CONTENT_ENCODING"]
  end

  test "handles empty gzip data" do
    empty_gzip = StringIO.new
    Zlib::GzipWriter.wrap(empty_gzip) { |gz| }

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "gzip",
      "rack.input" => StringIO.new(empty_gzip.string),
      "CONTENT_LENGTH" => empty_gzip.string.bytesize.to_s
    }

    status, headers, body = @middleware.call(env)

    assert_equal 200, status
    assert_equal "", env["rack.input"].read
    assert_equal "0", env["CONTENT_LENGTH"]
    assert_nil env["HTTP_CONTENT_ENCODING"]
  end

  test "respects maximum decompressed size limit" do
    # Create a large string that will exceed the limit when decompressed
    large_body = "x" * (CompressedRequest::MAX_DECOMPRESSED_SIZE + 1024)
    compressed_body = StringIO.new
    Zlib::GzipWriter.wrap(compressed_body) { |gz| gz.write(large_body) }

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "gzip",
      "rack.input" => StringIO.new(compressed_body.string)
    }

    assert_raises(StandardError) do
      @middleware.call(env)
    end
  end

  test "restores original body on Zlib errors" do
    # Create invalid gzip data that will trigger a Zlib error
    invalid_gzip = "\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x00corrupted"

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "gzip",
      "rack.input" => StringIO.new(invalid_gzip)
    }

    status, headers, body = @middleware.call(env)

    assert_equal 200, status
    env["rack.input"].rewind
    assert_equal invalid_gzip, env["rack.input"].read
    assert_equal "gzip", env["HTTP_CONTENT_ENCODING"]
  end

  test "re-raises non-Zlib errors after logging" do
    original_body = "Test body"
    compressed_body = StringIO.new
    Zlib::GzipWriter.wrap(compressed_body) { |gz| gz.write(original_body) }

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "gzip",
      "rack.input" => StringIO.new(compressed_body.string)
    }

    # Create a middleware that will raise a non-Zlib error
    error_raising_app = lambda { |env| raise StandardError, "Unexpected error" }
    middleware = CompressedRequest.new(error_raising_app)

    # Override stream_decompress to raise our error
    middleware.define_singleton_method(:stream_decompress) do |data|
      raise StandardError, "Unexpected error"
    end

    assert_raises(StandardError) do
      middleware.call(env)
    end
  end

  test "handles case-sensitive content encoding check" do
    body = "Test body"

    env = {
      "REQUEST_PATH" => "/extension/v1/pages",
      "HTTP_CONTENT_ENCODING" => "GZIP",
      "rack.input" => StringIO.new(body)
    }

    status, headers, body_response = @middleware.call(env)

    assert_equal 200, status
    env["rack.input"].rewind
    assert_equal body, env["rack.input"].read
    assert_equal "GZIP", env["HTTP_CONTENT_ENCODING"]
  end

  private

  def mock_app_with_verification
    lambda do |env|
      # Verify the decompressed content in the app
      body = env["rack.input"].read
      env["rack.input"].rewind
      [200, {"X-Body-Size" => body.bytesize.to_s}, [body]]
    end
  end
end