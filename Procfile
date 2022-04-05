worker: env DB_POOL=2 LIBRATO_AUTORUN=1 bundle exec sidekiq -c 2 -q critical,4 -q feed_refresher_receiver,3 -q default,2
worker_slow: env DB_POOL=2 bundle exec sidekiq -c 2 -q worker_slow_critical,2 -q worker_slow,1
worker_network: env DB_POOL=2 bundle exec sidekiq -c 2 -q search,2 -q low,1
clock: bundle exec clockwork lib/clock.rb
