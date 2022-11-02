STORAGE = {}.tap do |hash|
  hash[:provider]              = "AWS"
  hash[:aws_access_key_id]     = ENV["AWS_ACCESS_KEY_ID"]
  hash[:aws_secret_access_key] = ENV["AWS_SECRET_ACCESS_KEY"]
  hash[:region]                = ENV["AWS_S3_REGION"]     if ENV["AWS_S3_REGION"]
  hash[:host]                  = ENV["AWS_S3_HOST"]       if ENV["AWS_S3_HOST"]
  hash[:endpoint]              = ENV["AWS_S3_ENDPOINT"]   if ENV["AWS_S3_ENDPOINT"]
  hash[:path_style]            = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]
end
