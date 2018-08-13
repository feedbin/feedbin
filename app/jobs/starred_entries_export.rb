class StarredEntriesExport
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)
    file = Tempfile.new(["starred_", ".json"])
    build_file(user, file)
    upload_url = upload_file(file)
    UserMailer.starred_export_download(user_id, upload_url).deliver_now
  ensure
    file.close
    file.unlink
  end

  def build_file(user, file)
    starred_ids = user.starred_entries.order("created_at desc").pluck(:entry_id)
    file.write("[")
    starred_ids.each_slice(100) do |entry_ids|
      entries = Entry.where(id: entry_ids).includes(:feed)
      entries.each do |entry|
        json = MultiJson.dump(build_hash(entry))
        file.write("#{json},\n")
      end
    end
    file.close
    File.truncate(file.path, File.size(file.path) - 2)
    file = File.open(file.path, "a")
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
      created_at: entry.created_at.iso8601(6),
    }
  end
end
