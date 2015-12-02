worker: env DB_POOL=6 LIBRATO_AUTORUN=1 bundle exec sidekiq -c 6 -q critical,3 -q feed_refresher_receiver,2 -q default
worker_slow: env DB_POOL=2 bundle exec sidekiq -c 2 -q worker_slow
clock: bundle exec clockwork lib/clock.rb
sidekiq_web: bundle exec unicorn sidekiq/config.ru -p 2808