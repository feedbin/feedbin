class NewsletterSaver
  include Sidekiq::Worker
  sidekiq_options queue: :default_critical

  def perform(entry_id)
    entry = Entry.find(entry_id)
    page = NewsletterPage.new(entry)
    legacy_save(page)
    page.save
    url = page.url
    entry.update(url: url) if url && entry.url != url
  end

  # Until the CDN origin moves to B2 it still reads from S3, so a page saved
  # only to B2 would 404. This write goes first: a B2 failure then raises and
  # retries without leaving the page missing from S3. Unset
  # AWS_S3_BUCKET_NEWSLETTERS to stop the write.
  def legacy_save(page)
    bucket = ENV["AWS_S3_BUCKET_NEWSLETTERS"]
    return if bucket.blank?
    Fog::Storage.new(STORAGE).put_object(bucket, page.key, page.body, legacy_options(page))
  end

  def legacy_options(page)
    page.headers.merge(
      "Expires" => "Sun, 29 Jun 2036 17:48:34 GMT",
      "x-amz-acl" => "public-read",
      "x-amz-storage-class" => ENV["AWS_S3_STORAGE_CLASS"] || "REDUCED_REDUNDANCY"
    )
  end
end
