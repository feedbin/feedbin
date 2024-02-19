namespace :feedbin do
  desc "run db:reset, flush redis and restart pow"
  task :reset do
    db_name = "#{File.basename(Rails.root)}_#{Rails.env}"
    sh = "ps xa | grep postgres: | grep #{db_name} | grep -v grep | awk '{print $1}' | xargs kill"
    puts `#{sh}`

    FileUtils.mkdir_p(File.join(Rails.root, "tmp"))
    restart_file = File.join(Rails.root, "tmp", "restart.txt")
    Kernel.system "touch #{restart_file}"
    Kernel.system "rake --trace db:reset"
    Kernel.system "open '#{ENV["FEEDBIN_URL"]}/login'"
    Kernel.system "redis-cli 'flushdb'"
    Kernel.system "redis-cli -n 2 'flushdb'"
    Kernel.system "echo 'flush_all' | nc localhost 11211"
    Search.client { _1.request(:delete, "_all") }
  end
end
