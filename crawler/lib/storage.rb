STORAGE_OPTIONS = {
  provider: "AWS",
  aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  persistent: true
}
STORAGE_OPTIONS[:region] = ENV["AWS_S3_REGION"] if ENV["AWS_S3_REGION"]
STORAGE_OPTIONS[:host] = ENV["AWS_S3_HOST"] if ENV["AWS_S3_HOST"]
STORAGE_OPTIONS[:endpoint] = ENV["AWS_S3_ENDPOINT"] if ENV["AWS_S3_ENDPOINT"]
STORAGE_OPTIONS[:path_style] = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]
