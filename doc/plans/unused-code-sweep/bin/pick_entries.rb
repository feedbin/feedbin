# Click-through setup: pick one entry of each kind from the dev data, for the
# signed-in user (/auto_sign_in signs in User.first). Prints the feed title and
# the entry title, so the smoke route can click them by their visible text.
# Run with: bin/rails runner $SWEEP/bin/pick_entries.rb   (outside the sandbox: the DB is in OrbStack)
require_relative "lib"

user = User.first
feed_ids = user.subscriptions.pluck(:feed_id)
entries = Entry.where(feed_id: feed_ids).order(id: :desc).limit(5000).includes(:feed).to_a

kinds = {
  "podcast" => ->(e) { e.podcast? },
  "youtube" => ->(e) { e.youtube? },
  "tweet" => ->(e) { e.tweet? },
  "micropost" => ->(e) { e.micropost? },
  "newsletter" => ->(e) { e.newsletter? },
  "code" => ->(e) { e.content.to_s.include?("<pre") },
  "footnotes" => ->(e) { e.content.to_s.match?(/footnote|fnref/) },
  "default" => ->(e) { e.data.blank? || e.data["type"].blank? }
}

lines = kinds.map do |kind, test|
  e = entries.find(&test)
  e ? [kind, e.id, e.feed.title.to_s[0, 60], e.title.to_s.strip[0, 80]].join("\t") : "#{kind}\tNONE"
end
File.write(File.join(OUT, "smoke_entries.tsv"), "kind\tentry_id\tfeed_title\tentry_title\n" + lines.join("\n") + "\n")
puts "user: #{user.email}"
puts lines
