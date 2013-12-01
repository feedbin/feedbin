if Rails.env.development?
  Tire.configure { logger 'log/elasticsearch.log' }
end
