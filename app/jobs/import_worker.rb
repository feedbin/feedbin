class ImportWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(id)
    import = Import.find(id)
    extension = import.upload.file.extension.downcase
    if ["xml", "opml"].include?(extension)
      import.build_opml_import_job
    end
  end
end
