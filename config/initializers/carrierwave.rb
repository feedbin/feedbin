if ENV["AWS_ACCESS_KEY_ID"] && ENV["AWS_SECRET_ACCESS_KEY"]
  CarrierWave.configure do |config|
    config.fog_credentials = {
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      region: ENV["AWS_S3_REGION"] || "us-east-1",
      host: ENV["AWS_S3_HOST"] || "s3.amazonaws.com",
      endpoint: ENV["AWS_S3_ENDPOINT"] || nil,
      path_style: ENV["AWS_S3_PATH_STYLE"] || false,
    }
    config.fog_directory = ENV["AWS_S3_BUCKET"]
    config.max_file_size = 5.megabytes
  end
end
