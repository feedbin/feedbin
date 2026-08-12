STORAGE = {}.tap do |hash|
  hash[:provider]              = "AWS"
  hash[:aws_access_key_id]     = ENV["AWS_ACCESS_KEY_ID"]
  hash[:aws_secret_access_key] = ENV["AWS_SECRET_ACCESS_KEY"]
  hash[:region]                = ENV["AWS_S3_REGION"]     if ENV["AWS_S3_REGION"]
  hash[:host]                  = ENV["AWS_S3_HOST"]       if ENV["AWS_S3_HOST"]
  hash[:endpoint]              = ENV["AWS_S3_ENDPOINT"]   if ENV["AWS_S3_ENDPOINT"]
  hash[:path_style]            = ENV["AWS_S3_PATH_STYLE"] if ENV["AWS_S3_PATH_STYLE"]
end

STORAGE_R2 = {}.tap do |hash|
  hash[:provider]              = "AWS"
  hash[:aws_access_key_id]     = ENV["R2_ACCESS_KEY_ID"]
  hash[:aws_secret_access_key] = ENV["R2_SECRET_ACCESS_KEY"]
  hash[:endpoint]              = ENV["R2_ENDPOINT"] if ENV["R2_ENDPOINT"]
  hash[:region]                = ENV["R2_REGION"] || "auto"
  hash[:path_style]            = true
end
