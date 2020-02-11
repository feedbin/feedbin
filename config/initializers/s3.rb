if ENV["AWS_ACCESS_KEY_ID"]
  S3_POOL = ConnectionPool.new(size: 10, timeout: 5) {
    options = {
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      persistent: true,
    }
    options[:region] = ENV["AWS_S3_REGION"] if ENV["AWS_S3_REGION"]
    options[:host] = ENV["AWS_S3_HOST"] if ENV["AWS_S3_HOST"]
    options[:endpoint] = ENV["AWS_S3_ENDPOINT"] if ENV["AWS_S3_ENDPOINT"]
    options[:path_style] = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]
    Fog::Storage.new(options)
  }
end
