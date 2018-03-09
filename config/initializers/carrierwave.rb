if ENV["AWS_ACCESS_KEY_ID"] && ENV["AWS_SECRET_ACCESS_KEY"]
  CarrierWave.configure do |config|
    config.fog_provider = 'fog/aws'
    if ENV["MINIO_HOST"] && ENV["MINIO_ENDPOINT"]
      config.fog_credentials = {
        provider: "AWS",
        aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
        host: ENV["MINIO_HOST"],
        endpoint: ENV["MINIO_ENDPOINT"],
        path_style: true
      }
    else
      config.fog_credentials = {
        provider: "AWS",
        aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
      }
    end
    config.fog_directory = ENV["AWS_S3_BUCKET"]
    config.max_file_size = 75.megabytes
  end
end