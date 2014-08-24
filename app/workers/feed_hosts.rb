class FeedHosts
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(batch)
    batch_size = 1000
    start = ((batch - 1) * batch_size) + 1
    finish = batch * batch_size
    ids = (start..finish).to_a

    values = []
    feeds = Feed.where(id: ids).pluck(:id, :site_url)
    feeds.each do |(id, site_url)|
      values << value(id, site_url)
    end
    values = values.join(", ")

    query = update_query % values
    ActiveRecord::Base.connection.execute(query)
  end

  def value(id, site_url)
    host = get_host(site_url)
    if host
      host = "'%s'" % host
    else
      host = 'NULL'
    end
    "(%d, %s)" % [id, host]
  end

  def get_host(url)
    URI::parse(url).host
  rescue
    nil
  end

  def update_query
    <<-eos
      UPDATE feeds AS feeds_table SET
          host = data.host
      FROM (
      	VALUES %s
      ) AS data(id, host)
      WHERE data.id = feeds_table.id;
    eos
  end


end