class UpdateDefaultColumn
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(options = {})
    @klass = options.fetch("klass").constantize
    @column = options.fetch("column")
    @default = options.fetch("default")

    if options["schedule"]
      schedule
    else
      @batch = options.fetch("batch")
      set_default
    end
  end

  def set_default
    @klass.reset_column_information
    ids = build_ids(@batch)
    @klass.where(id: ids).update_all(@column => @default)
  end

  def schedule
    jobs = job_args(@klass.last.id, @klass.first.id).map { |arg|
      [{
        "batch" => arg.first,
        "klass" => @klass.to_s,
        "column" => @column,
        "default" => @default,
      }]
    }
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => self.class.name,
      "queue" => self.class.get_sidekiq_options["queue"].to_s,
    )
  end
end
