# The single scope full becomes read write, plus account for Feedbin's own
# apps (see Api::V3::Scopes). The only first-party app that exists in code is
# the development one; a production app gets account from
# rake api_v3:first_party[UID].
class SplitFullScope < ActiveRecord::Migration[8.1]
  DEVELOPMENT_UID = "feedbin-next-development"

  def up
    # Data only: rewrites a string column, no locks beyond the rows.
    safety_assured do
      execute sanitize("UPDATE oauth_applications SET scopes = :first_party WHERE uid = :uid", first_party: "read write account", uid: DEVELOPMENT_UID)
      %w[oauth_access_tokens oauth_access_grants].each do |table|
        execute sanitize(<<~SQL, first_party: "read write account", uid: DEVELOPMENT_UID, full: "full")
          UPDATE #{quote_table_name(table)} SET scopes = :first_party
          WHERE scopes = :full AND application_id IN (SELECT id FROM oauth_applications WHERE uid = :uid)
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
