init_redis: redis-server
feedbin_clock: bundle exec clockwork lib/clock.rb
feedbin_jobs: DB_POOL=10 bundle exec sidekiq --config config/sidekiq-development.yml
feedbin_css: bin/rails tailwindcss:watch
web: bundle exec rails server -p 3000