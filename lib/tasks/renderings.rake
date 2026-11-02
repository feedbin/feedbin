namespace :renderings do
  desc "Record ContentFormatter::VERSION and its fingerprint for the test suite"
  task fingerprint: :environment do
    path = Rails.root.join("test/fixtures/files/content_formatter_fingerprint.txt")
    File.write(path, "#{ContentFormatter::VERSION} #{ContentFormatter.fingerprint}\n")
    puts File.read(path)
  end

  desc "Re-render stored entry renderings. FEED=<id> and/or SINCE=<date> re-render those in place; with neither, every entry goes into a fresh table for renderings:swap. FORCE=1 starts over."
  task rebuild: :environment do
    force = ENV["FORCE"] == "1"
    if ENV["SINCE"].present?
      # A date that does not parse must not fall through to a full pass.
      since = Time.zone.parse(ENV["SINCE"]) or abort("SINCE= is not a date.")
    end

    if ENV["FEED"].present?
      # The feed_id index includes created_at, so this is an index-only pluck.
      scope = Entry.where(feed_id: Integer(ENV["FEED"]))
      scope = scope.where(created_at: since..) if since
      jobs = RenderingsRebuild.start(ids: scope.pluck(:id), force: force)
      puts "Enqueued #{jobs} jobs to re-render in place. Watch with rails renderings:status."
    elsif since
      # Nothing indexes created_at alone, so the date becomes an id range.
      from_id = RenderingsRebuild.first_id_created_since(since) or abort("No entries created since #{since}.")
      jobs = RenderingsRebuild.start(from_id: from_id, force: force)
      puts "Enqueued #{jobs} jobs to re-render entries from id #{from_id} in place. Watch with rails renderings:status."
    else
      RenderingsRebuild.prepare_table(force: force)
      jobs = RenderingsRebuild.start(table: RenderingsRebuild::NEW_TABLE, force: force)
      puts "Enqueued #{jobs} jobs into #{RenderingsRebuild::NEW_TABLE}. Watch with rails renderings:status; when pending reaches 0, finish with rails renderings:swap."
    end
  end

  desc "Show the progress of the current rebuild"
  task status: :environment do
    RenderingsRebuild.progress.each { |name, count| puts "#{name}: #{count}" }
  end

  desc "Replace entry_renderings with the table a full rebuild wrote"
  task swap: :environment do
    attempts = RenderingsRebuild.swap
    puts "entry_renderings replaced (attempts: #{attempts}). Rows written during the rebuild render again on their next read."
  end
end
