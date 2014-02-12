require 'yajl'

class StarredEntriesExport
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(user_id)
    user = User.find(user_id);
    starred_ids = user.starred_entries.order('created_at desc').pluck(:entry_id)
    file = Tempfile.new('starred')
    encoder = Yajl::Encoder.new
    starred_ids.each_slice(5) do |entry_ids|
      entries = Entry.where(id: entry_ids).includes(:feed)
      entries.each do |entry|
        hash = build_hash(entry)
        encoder.encode(hash, file)
      end
    end
    path = file.path
    file.close
    path
  end

  def build_hash(entry)
    {
      id: entry.id,
      title: entry.title,
      author: entry.author,
      content: entry.content,
      url: entry.fully_qualified_url,
      published: entry.published.iso8601(6),
      created_at: entry.created_at.iso8601(6)
    }
  end

end
