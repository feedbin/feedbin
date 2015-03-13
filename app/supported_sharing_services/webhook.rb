class Webhook < Service

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params)
    WebhookSend.perform_async(@klass.id, params[:entry_id])
    200
  end

end