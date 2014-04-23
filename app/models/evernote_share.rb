class EvernoteShare
  URL = "https://sandbox.evernote.com"

  # 1. evernote = EvernoteShare.new
  # 2. client = evernote.request_token
  # 3. session[:evernote_token] = client.token; session[:evernote_secret] = client.secret
  # 4. redirect_to client.authorize_url
  # 5. evernote = EvernoteShare.new
  # 6. access_token = evernote.request_access(session[:evernote_token], session[:evernote_secret], params[:oauth_verifier])
  # 7. save access_token.token and access_token.secret in the database

  def initialize(token = nil)
    if token
      @token = token
      @client = EvernoteOAuth::Client.new(token: @token)
    end
  end

  def consumer
    options = {
      site: URL,
      request_token_path: '/oauth',
      authorize_path: '/OAuth.action',
      access_token_path: '/oauth'
    }
    OAuth::Consumer.new(ENV['EVERNOTE_KEY'], ENV['EVERNOTE_SECRET'], options)
  end

  def request_token
    consumer.get_request_token(oauth_callback: redirect_uri)
  end

  def request_access(oauth_token, oauth_token_secret, oauth_verifier)
    params = {oauth_token: oauth_token, oauth_token_secret: oauth_token_secret, }
    client = OAuth::RequestToken.from_hash(consumer, params)
    client.get_access_token(oauth_verifier: oauth_verifier)
  end

  def redirect_uri
    Rails.application.routes.url_helpers.oauth_response_supported_sharing_service_url('evernote', host: ENV['PUSH_URL'])
  end

  def add(params)
    note = Evernote::EDAM::Type::Note.new
    note.title = params[:title]
    note.content = params[:content]
    note.notebookGuid = params[:notebook_guid]
    if params[:tags].present?
      note.tagNames = params[:tags].split(',').map {|tag| tag.strip}
    end
    note_store = @client.note_store
    note_store.createNote(@token, note)
  end

  def notebooks
    note_store = @client.note_store
    note_store.listNotebooks(@token)
  end

end
