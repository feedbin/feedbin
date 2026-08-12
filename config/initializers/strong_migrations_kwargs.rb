# strong_migrations 1.8.0 wraps ActiveRecord::Tasks::DatabaseTasks.migrate as
# `def migrate(*args)`, which accepts no keyword arguments. Rails 8.1 calls it as
# `migrate(skip_initialize: true)`, so Ruby collapses the keyword into a positional Hash
# and it arrives as the `version` argument. Rails then filters migrations with
# `migration.version == version`, comparing an Integer to a Hash, which matches nothing:
# `rake db:migrate` silently applies no migrations and exits 0.
#
# ruby2_keywords marks the wrapper so the trailing Hash is forwarded to super as keywords
# again, leaving `version` nil. It keeps the gem's backtrace cleaning intact.
#
# Fixed upstream in strong_migrations 2.0.2, which we cannot take: 2.0.0 raises
# UnsupportedVersion on Postgres < 12 and production runs Postgres 11. 1.8.0 is the final
# 1.x release, so there is no backport. Remove this along with the `< 2` pin in the
# Gemfile once Postgres is upgraded.
if defined?(StrongMigrations::DatabaseTasks)
  StrongMigrations::DatabaseTasks.send(:ruby2_keywords, :migrate)
end
