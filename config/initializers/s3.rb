if ENV["AWS_ACCESS_KEY_ID"]
  S3_POOL = ConnectionPool.new(size: 10, timeout: 5) {
    Fog::Storage.new(
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      persistent: true,
    )
  }
end
