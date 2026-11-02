# The single scope full becomes read write, plus account for Feedbin's own
# apps (see Api::V3::Scopes): the development app, and the production apps
# named in API_V3_FIRST_PARTY_UIDS. rake api_v3:first_party[UID] marks one
# later.
class SplitFullScope < ActiveRecord::Migration[8.1]
  DEVELOPMENT_UID = "feedbin-next-development"

  def up
    uids = [DEVELOPMENT_UID, *Api::V3::Scopes.first_party_uids]
    # Data only: rewrites a string column, no locks beyond the rows.
    safety_assured do
      execute sanitize("UPDATE oauth_applications SET scopes = :first_party WHERE uid IN (:uids)", first_party: "read write account", uids: uids)
      # An app's own scopes bound what it may be issued, so one stored as full
      # could no longer authorize at all. Empty means the server's scopes.
      execute sanitize("UPDATE oauth_applications SET scopes = '' WHERE scopes = :full", full: "full")
      %w[oauth_access_tokens oauth_access_grants].each do |table|
        execute sanitize(<<~SQL, first_party: "read write account", uids: uids, full: "full")
          UPDATE #{quote_table_name(table)} SET scopes = :first_party
          WHERE scopes = :full AND application_id IN (SELECT id FROM oauth_applications WHERE uid IN (:uids))
        SQL
        execute sanitize("UPDATE #{quote_table_name(table)} SET scopes = :default WHERE scopes = :full", default: "read write", full: "full")
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def sanitize(sql, binds)
    ActiveRecord::Base.sanitize_sql_array([sql, binds])
  end
end
