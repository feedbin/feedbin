class Share::EvernoteShare < Share::Service
  URL = "https://www.evernote.com"

  # 1. evernote = EvernoteShare.new
  # 2. client = evernote.request_token
  # 3. session[:evernote_token] = client.token; session[:evernote_secret] = client.secret
  # 4. redirect_to client.authorize_url
  # 5. evernote = EvernoteShare.new
  # 6. access_token = evernote.request_access(session[:evernote_token], session[:evernote_secret], params[:oauth_verifier])
  # 7. save access_token.token and access_token.secret in the database

  def initialize(klass = nil)
    if klass.present? && klass.access_token.present?
      @klass = klass
      @token = @klass.access_token
      @client = EvernoteOAuth::Client.new(token: @token, sandbox: false)
    end
  end

  def consumer
    options = {
      site: URL,
      request_token_path: "/oauth",
      authorize_path: "/OAuth.action",
      access_token_path: "/oauth",
    }
    OAuth::Consumer.new(ENV["EVERNOTE_KEY"], ENV["EVERNOTE_SECRET"], options)
  end

  def request_token
    consumer.get_request_token(oauth_callback: redirect_uri)
  end

  def request_access(oauth_token, oauth_token_secret, oauth_verifier)
    params = {oauth_token: oauth_token, oauth_token_secret: oauth_token_secret}
    client = OAuth::RequestToken.from_hash(consumer, params)
    client.get_access_token(oauth_verifier: oauth_verifier)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url("evernote", host: ENV["PUSH_URL"])
  end

  def response_valid?(session, params)
    params[:oauth_verifier].present?
  end

  def share(params)
    @klass.update(default_option: params[:notebook_guid])
    authenticated_share(@klass, params)
  end

  def add(params)
    entry = Entry.find(params[:entry_id])
    content = determine_content(params)
    content = ContentFormatter.evernote_format(content, entry)
    view_paths = Rails::Application::Configuration.new(Rails.root).paths["app/views"]
    action_view = ActionView::Base.new(view_paths)
    params[:content] = action_view.render(partial: "supported_sharing_services/evernote_note", locals: {content: content.html_safe})

    attributes = Evernote::EDAM::Type::NoteAttributes.new
    attributes.subjectDate = entry.published.to_i
    attributes.source = entry.feed.title
    attributes.sourceURL = entry.fully_qualified_url
    attributes.sourceApplication = "Feedbin"
    if entry.author.present?
      attributes.author = entry.author
    end

    note = Evernote::EDAM::Type::Note.new
    note.attributes = attributes
    note.title = params[:title]
    note.content = params[:content]
    note.notebookGuid = params[:notebook_guid]
    if params[:tags].present?
      note.tagNames = params[:tags].split(",").map { |tag| tag.strip }
    end
    note_store.createNote(@token, note)
    200
  rescue => exception
    if exception.respond_to?(:errorCode) && exception.errorCode == Evernote::EDAM::Error::EDAMErrorCode::AUTH_EXPIRED
      401
    else
      parameters = {exception: exception}
      if exception.respond_to?(:errorCode)
        parameters[:error_code] = exception.errorCode
      end
      if exception.respond_to?(:parameter)
        parameters[:parameter] = exception.parameter
      end
      Honeybadger.notify(
        error_class: "EvernoteShare#add",
        error_message: "EvernoteShare add failure",
        parameters: parameters,
      )
      500
    end
  end

  def after_activate
    get_notebook_options
  end

  def get_notebook_options
    notebook_options = {}
    notebooks.each do |notebook|
      notebook_options[notebook.name] = notebook.guid
    end
    notebook_options
  end

  def note_store
    @note_store ||= @client.note_store
  end

  def notebooks
    note_store.listNotebooks(@token)
  end
end
