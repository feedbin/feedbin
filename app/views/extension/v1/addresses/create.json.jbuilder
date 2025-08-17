if @verified_token
  json.partial! "extension/v1/addresses/new"
else
  json.created true
  json.email @record.title
  json.addresses @addresses do |address|
    json.email address.title
    json.description address.description
  end
end