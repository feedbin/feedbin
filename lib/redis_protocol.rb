#!/usr/bin/env ruby

require 'time'
require 'optparse'
ENV['TZ'] = 'UTC'

def gen_redis_proto(*cmd)
  proto = ""
  proto << "*" + cmd.length.to_s + "\r\n"
  cmd.each do |arg|
    proto << "$" + arg.to_s.bytesize.to_s + "\r\n"
    proto << arg.to_s + "\r\n"
  end
  proto
end

def get_score(time)
  score = Time.parse(time)
  "%10.6f" % score.to_f
end

opts = {}
OptionParser.new do |options|
  options.set_banner "Usage: redis_protocol.rb [options] [files]\n" \
    "Generate redis protocol from the output of:\n" \
    "COPY entries (id, feed_id, public_id, created_at, published) TO '/tmp/redis_data';"

  options.separator ""
  options.separator "Options:"

  options.on("--data DATA", "Specify which data you want. Options: public_id, created_at, published") do |data|
    opts[:data] = data
  end

  options.on_tail("-h", "--help") do
    $stderr.puts options
    exit 1
  end
end.parse!

while input = ARGF.gets
  input.each_line do |line|

    line = line.chop

    entry_id, feed_id, public_id, created_at, published = line.split("\t")

    begin
      case opts[:data]
      when "public_id"
        $stdout.write(gen_redis_proto("HSET", "entry:public_ids:#{public_id[0..4]}", public_id, 1))
      when "created_at"
        score = get_score(created_at)
        $stdout.write(gen_redis_proto("ZADD", "feed:#{feed_id}:entry_ids:created_at", score, entry_id))
      when "published"
        score = get_score(published)
        $stdout.write(gen_redis_proto("ZADD", "feed:#{feed_id}:entry_ids:published", score, entry_id))
      else
        $stderr.puts "--data needs to be specified"
        exit 1
      end
    rescue Errno::EPIPE
      exit(74)
    end
  end
end
