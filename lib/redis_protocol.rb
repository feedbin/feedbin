#!/usr/bin/env ruby

require "optparse"
require "redis"
ENV["TZ"] = "UTC"

def gen_redis_proto(*cmd)
  proto = ""
  proto << "*" + cmd.length.to_s + "\r\n"
  cmd.each do |arg|
    proto << "$" + arg.to_s.bytesize.to_s + "\r\n"
    proto << arg.to_s + "\r\n"
  end
  proto
end

opts = {}
OptionParser.new { |options|
  banner = <<-EOD
    Usage: redis_protocol.rb [options] [files]\n
    Generate redis protocol from the output of:\n
    psql -d feedbin -c "COPY (SELECT id, feed_id, public_id, EXTRACT(EPOCH FROM created_at AT TIME ZONE 'UTC'), EXTRACT(EPOCH FROM published AT TIME ZONE 'UTC') FROM entries) TO STDOUT;" | ./redis_protocol.rb --data internal | redis-cli --pipe
  EOD

  options.set_banner banner

  options.separator ""
  options.separator "Options:"

  options.on("--data DATA", "Specify which data you want. Options: public_id, internal") do |data|
    opts[:data] = data
  end

  options.on_tail("-h", "--help") do
    warn options
    exit 1
  end
}.parse!

while input = ARGF.gets
  input.each_line do |line|
    line = line.chop

    entry_id, feed_id, public_id, created_at, published = line.split("\t")

    begin
      case opts[:data]
      when "public_id"
        $stdout.write(gen_redis_proto("SET", public_id, 1))
      when "internal"
        $stdout.write(gen_redis_proto("ZADD", "feed:#{feed_id}:entry_ids:created_at", created_at, entry_id))
        $stdout.write(gen_redis_proto("ZADD", "feed:#{feed_id}:entry_ids:published", published, entry_id))
      else
        warn "--data needs to be specified"
        exit 1
      end
    rescue Errno::EPIPE
      exit(74)
    end
  end
end
