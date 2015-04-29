json.array!(@actions) do |action|
  json.partial! "api/v2/actions/action", action: action
end
