worker: env DB_POOL=12 LIBRATO_AUTORUN=1 bundle exec sidekiq -c 12 -q critical,3 -q feed_refresher_receiver,2 -q default
worker_slow: env DB_POOL=2 bundle exec sidekiq -c 2 -q worker_slow_critical,3 -q worker_slow,2 -q favicon,1
clock: bundle exec clockwork lib/clock.rb