json.extract! user, :expires_at
json.plan user.plan.stripe_id
json.app_token user.authentication_tokens.app.first&.uuid
json.newsletter_address user.newsletter_address
json.podcast_sort_order user.podcast_sort_order || "custom"
json.download_limit (user.podcast_download_limit || 10).to_i
