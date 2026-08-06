class StarredEntriesExport
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)
    file = Tempfile.new(["starred_", ".json"])
    build_file(user, file)
    upload_url = upload_file(file)
    UserMailer.starred_export_download(user_id, upload_url).deliver_now
  # The lookup runs before the tempfile exists, and a user who exports and then
  # closes their account is the ordinary way it fails -- so the cleanup has to
  # survive being reached with nothing to clean up, or it discards the
  # RecordNotFound on its way out.
  ensure
    file&.close
    file&.unlink
  end

  # The separator goes before every entry but the first, so nothing has to be
  # truncated off the end afterwards. Trimming the trailing ",\n" by byte count
  # asked the kernel to truncate to -1 whenever no entry was written -- an
  # account with nothing starred, or one whose stars have all aged out of the
  # entries table.
  def build_file(user, file)
    starred_ids = user.starred_entries.order("created_at desc").pluck(:entry_id)
    file.write("[")
    first = true
    starred_ids.each_slice(100) do |entry_ids|
      entries = Entry.where(id: entry_ids).includes(:feed)
      entries.each do |entry|
        file.write(",\n") unless first
        file.write(JSON.generate(build_hash(entry)))
        first = false
      end
    end
    file.write("]")
    file.close
  end

  def upload_file(file)
    file = File.open(file)
    uploader = StarredExportUploader.new
    uploader.store!(file)
    uploader.url
  end

  def build_hash(entry)
    {
      id: entry.id,
      title: entry.title,
      author: entry.author,
      content: ContentFormatter.api_format(entry.content, entry),
      url: entry.fully_qualified_url,
      published: entry.published.iso8601(6),
      created_at: entry.created_at.iso8601(6)
    }
  end
end
