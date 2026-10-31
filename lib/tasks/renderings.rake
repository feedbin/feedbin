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
    scope = Entry.all
    scope = scope.where(feed_id: Integer(ENV["FEED"])) if ENV["FEED"].present?
    scope = scope.where(created_at: Date.parse(ENV["SINCE"])..) if ENV["SINCE"].present?

    if ENV["FEED"].present? || ENV["SINCE"].present?
      jobs = RenderingsRebuild.start(ids: scope.pluck(:id), force: force)
      puts "Enqueued #{jobs} jobs to re-render in place. Watch with rails renderings:status."
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
    result = RenderingsRebuild.swap
    puts "Carried over #{result[:copied]} rows written during the rebuild. entry_renderings now has #{result[:rows]} rows."
  end
end
