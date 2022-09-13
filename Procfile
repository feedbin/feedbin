feedbin_core:     env DB_POOL=2 LIBRATO_AUTORUN=1 bundle exec sidekiq -c 2 -q critical,4 -q feed_refresher_receiver,3 -q default,2
feedbin_slow:     env DB_POOL=2 bundle exec sidekiq -c 2 -q worker_slow_critical,2 -q worker_slow,1
feedbin_network:  env DB_POOL=2 bundle exec sidekiq -c 2 -q search,2 -q low,1
feedbin_parser:   env DB_POOL=1 bundle exec sidekiq --concurrency 1  --queue feed_parser_critical_$HOSTNAME,2  --queue feed_parser_$HOSTNAME
feedbin_twitter:  env DB_POOL=2 bundle exec sidekiq --concurrency 2  --queue twitter_refresher_critical,2  --queue twitter_refresher
clock:           bundle exec clockwork lib/clock.rb
