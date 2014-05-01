class RefreshEvernoteNotebooks
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)
    evernote_notebooks = {}
    evernote = @user.supported_sharing_services.where(service_id: 'evernote').first
    if evernote.present?
      notebooks = evernote.evernote_notebooks
      notebooks.each do |notebook|
        evernote_notebooks[notebook.name] = notebook.guid
        if notebook.defaultNotebook
          evernote_selected = notebook.guid
        end
      end
    end
  end

end