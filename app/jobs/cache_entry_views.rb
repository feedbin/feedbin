class CacheEntryViews
  include Sidekiq::Worker

  def perform(entry_id)
    entries = Entry.where(id: entry_id)
    json_cache("api/v2/entries/_entry_extended", entries, :entry, {}, false)
  rescue ActiveRecord::RecordNotFound
  end

  def json_cache(template_path, records, local, params, *cache_keys)
    controller = ApplicationController.renderer.new.controller.new
    template = controller.lookup_context.find(template_path)
    digest_path = controller.helpers.digest_path_from_template(template)

    keys = records.map do |record|
      controller.helpers.cache_fragment_name([cache_keys, record], virtual_path: template, digest_path: digest_path)
    end

    results = Rails.cache.fetch_multi(*keys) do |key|
      ApplicationController.render template: template.virtual_path, locals: {local => key.flatten.last, params: params}, format: :json
    end

    results.values.join(",")
  end

end
