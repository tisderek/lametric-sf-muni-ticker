require "sinatra"
require "json"
require "uri"
require "ox"
require "ostruct"
require "pry"

NEXTBUS_BASE_URL = 'http://webservices.nextbus.com/service/publicXMLFeed?command=predictions&a=sf-muni'

ICONS = {
  LOGO:   'i21026',
  J:      'i20870',
  T:      'i20989',
  M:      'i20996',
  K:      'i20995',
  L:      'i21011',
  N:      'i21025'
}

DEFAULT_PREDICTIONS_PER_FRAME = 1
DEFAULT_MAX_PREDICTIONS_PER_ROUTE = 2

def to_recursive_ostruct(hash)
  OpenStruct.new(hash.each_with_object({}) do |(key, val), memo|
    memo[key] = val.is_a?(Hash) ? to_recursive_ostruct(val) : val
  end)
end

def fetch_stop_predictions(stop_id, route_tag)
  url = "#{NEXTBUS_BASE_URL}&stopId=#{stop_id}&routeTag=#{route_tag}"
  xml = Net::HTTP.get_response(URI.parse(url)).body
  predictions = to_recursive_ostruct(Ox.load(xml, mode: :hash)[:body][1])
end

def stop_predictions(stop_id, route_tag)
  xml = fetch_stop_predictions(stop_id, route_tag)
  predictions = dig_predictions(xml)
  parse_predictions(predictions)
end

def fetch_stop_predictions(stop_id, route_tag)
  url = "#{NEXTBUS_BASE_URL}&stopId=#{stop_id}&routeTag=#{route_tag}"
  xml = Net::HTTP.get_response(URI.parse(url)).body
end

def dig_predictions(xml)
  x = to_recursive_ostruct(Ox.load(xml, mode: :hash)).body[1]
  binding.pry
  x[:predictions][1][:direction]
    .map{ |x| to_recursive_ostruct(x) }
    .find_all(&:prediction)
end

def parse_predictions(predictions)
  predictions.map { |x| x.prediction[0][:minutes] }.flatten
end

def present_pairs(predictions)

end

def present_singles(predictions)
  max_predictions_per_route = DEFAULT_MAX_PREDICTIONS_PER_ROUTE
  predictions.each_with_index.map do | minutes, idx |
    next if idx >  max_predictions_per_route - 1
    if minutes.to_i === 0
      {text: 'NOW'}
    else
      {text: minutes + ' MIN'} 
    end
  end
end

def serialize_frames(frames, opts = {})
  serialized = frames.each_with_index.map do |x, idx|
    {
      :index => idx,
      :icon => opts.dig(:default_icon) || x.dig(:icon) || ICONS[:LOGO],
      :text => x.dig(:text) || x.class == String && x
    }
  end

  {:frames => serialized}.to_json
end

def crop_predictions(predictions)
  predictions.take(DEFAULT_MAX_PREDICTIONS_PER_ROUTE)
end

get "/predictions" do
  cache_control :public, max_age: 540
  content_type :json

  errors = []
  errors << {text: "STOP_ID?"} unless params[:stop_id]
  errors << {text: "ROUTES?"} unless params[:routes]

  if errors.any?
    return serialize_frames(errors, default_icon: ICONS[:LOGO])
  end

  predictions = stop_predictions(params[:stop_id], params[:routes]) # [0, 4, 11, 19, 44]
  # cropping takes into consideration max predictions per route
  # cropped_predictions = 
  #   crop_predictions(
  #     params[:max_predictions_per_route] 
  #     || DEFAULT_MAX_PREDICTIONS_PER_ROUTE)
  #   ) # [ 0, 4 ]

  # present turns 0 to NOW and adds min depending on params
  presented_predictions = present_singles(crop_predictions(predictions)) # ["NOW", "4 MIN"]
  puts 'presented_predictions '
  puts presented_predictions 
    # if params[:predictions_per_line].to_i == 2
    #   present_pairs(predictions)
    # else
      # present_singles(predictions)
    # end
  puts 'serialize_frames(presented_predictions) '
  puts serialize_frames(presented_predictions, default_icon: ICONS[params[:routes].to_sym]) 
  # serialize adds the indexes to the array passed in and turns to json
  serialize_frames(presented_predictions, default_icon: ICONS[params[:routes].to_sym]) 
end

