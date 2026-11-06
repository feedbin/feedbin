require "test_helper"
require_relative "api_docs"

# Skipped unless feedbin-api-docs is checked out beside this repo (or at API_DOCS).
class ApiDocsExamplesTest < ActionDispatch::IntegrationTest
  setup do
    @environment = ApiDocs::ENVIRONMENT.keys.index_with { ENV[it] }
    ApiDocs::ENVIRONMENT.each { |key, value| ENV[key] = value }
    travel_to ApiDocs::NOW
    host! ApiDocs::HOST
    https!
    Rails.cache.clear
    clear_search
    ApiDocs::World.build
  end

  teardown do
    @environment&.each { |key, value| ENV[key] = value }
  end

  if File.directory?(ApiDocs.docs_root)
    ApiDocs::Page.endpoints(ApiDocs.docs_root).each do |page|
      test "endpoint #{page.key}" do
        examples_for(page).each { |path, example| check(path, example) }
      end
    end

    ApiDocs.examples.each do |example|
      test "#{example.kind} #{example.name}" do
        examples_from(example).each { |path, json| check(path, json) }
      end
    end
  end

  private

  # => {docs-relative path => example}
  def examples_for(page)
    scenario = ApiDocs.scenarios[page.key]
    per_source = scenario&.per_source || page.tokens.include?("entry_id")
    sources = per_source ? ApiDocs.sources : ApiDocs.sources.first(1)
    sources.to_h do |source|
      path = per_source ? "_data/responses/#{page.key}/#{source["key"]}.json" : "_data/responses/#{page.key}.json"
      [path, isolated(scenario, source) { perform(page, scenario, source) }]
    end
  end

  def examples_from(example)
    sources = example.per_source ? ApiDocs.sources : ApiDocs.sources.first(1)
    sources.to_h do |source|
      name = example.per_source ? "#{example.name}/#{source["key"]}" : example.name
      json = isolated(example, source) do
        headers = headers(true)
        headers["Content-Type"] = "application/json" if example.body
        process(example.method, "/v3#{example.path.gsub(ApiDocs::Page::TOKEN) { source.fetch($1) }}", params: example.body, headers: headers)
        assert_response :success, "#{example.name}: #{response.body}"
        recorded
      end
      value = if example.kind == "snippets" then json
      elsif example.pick then json["body"].dig(*pointer(example.pick))
      else json["body"]
      end
      ["_data/#{example.kind}/#{name}.json", value]
    end
  end

  def isolated(scenario, source)
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      ApiDocs::Sequences.reset
      Rails.cache.clear
      instance_exec(source, &scenario.setup) if scenario&.setup
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end

  def perform(page, scenario, source)
    request = scenario&.request&.call(source) || {}
    body = request.fetch(:body) { page.body(source) }
    headers = headers(page.authenticated?)
    headers["Content-Type"] = request.fetch(:content_type, "application/json") if body
    query = page.query(source)
    url = query.any? ? "#{page.path(source)}?#{URI.encode_www_form(query)}" : page.path(source)

    process(page.method, url, params: body, headers: headers)
    expected = page.front_matter.dig("response", "status")
    assert_equal expected, response.status, "#{page.key} (#{source["key"]}): #{response.body}" if expected

    recorded
  end

  def recorded
    {"status" => response.status, "content_type" => response.media_type, "body" => response_body}
  end

  def headers(authenticated)
    headers = {"X-Request-Id" => ApiDocs::REQUEST_ID}
    headers["Authorization"] = "Bearer #{ApiDocs::TOKEN}" if authenticated
    headers
  end

  def response_body
    return nil if response.body.empty?
    response.media_type.to_s.end_with?("json") ? JSON.parse(response.body) : response.body
  end

  def pointer(text)
    text.split("/").map { it.match?(/\A\d+\z/) ? it.to_i : it }
  end

  def check(path, example)
    file = File.join(ApiDocs.docs_root, path)
    json = "#{JSON.pretty_generate(example)}\n"
    if ApiDocs.write?
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, json)
    else
      assert File.exist?(file), "#{path} is missing. Run bin/rails api_docs:examples."
      assert_equal File.read(file), json, "#{path} is out of date. Run bin/rails api_docs:examples."
    end
  end
end
