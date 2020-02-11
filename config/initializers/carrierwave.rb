if ENV["AWS_ACCESS_KEY_ID"] && ENV["AWS_SECRET_ACCESS_KEY"]
  CarrierWave.configure do |config|
    options = {
      provider: "AWS",
      aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    }
    options[:region] = ENV["AWS_S3_REGION"] if ENV["AWS_S3_REGION"]
    options[:host] = ENV["AWS_S3_HOST"] if ENV["AWS_S3_HOST"]
    options[:endpoint] = ENV["AWS_S3_ENDPOINT"] if ENV["AWS_S3_ENDPOINT"]
    options[:path_style] = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]
    config.fog_credentials = options
    config.fog_directory = ENV["AWS_S3_BUCKET"]
    config.max_file_size = 5.megabytes
  end
end
