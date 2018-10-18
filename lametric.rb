require "sinatra"
require "json"
require "uri"
require "ox"
require "ostruct"
require "pry"
require 'net/http'

NEXTBUS_BASE_URL = 'http://webservices.nextbus.com/service/publicXMLFeed?command=predictions&a=sf-muni'

ICONS = {
  LOGO:   'i21078',
  J:      'i21079',
  # T:      'i20989',
  M:      'i21092',
  KT:     'i21088',
  L:      'i21095',
  N:      'i21093'
}

DEFAULT_PREDICTIONS_PER_FRAME = 1
DEFAULT_MAX_PREDICTIONS_PER_ROUTE = 4

def deep_transform_to_ostruct(hash)
  json = hash.to_json
  object = JSON.parse(json, object_class: OpenStruct)
end

def find(obj, key)
  obj.find(&key).send(key)
end

def fetch_stop_predictions(stop_id, route_tag)
  url = "#{NEXTBUS_BASE_URL}&stopId=#{stop_id}&routeTag=#{route_tag}"
  resp = Net::HTTP.get_response(URI.parse(url)).body
  xml = deep_transform_to_ostruct(Ox.load(resp, mode: :hash))
  xml.body.find(&:predictions)&.send(:predictions)
end

def stop_predictions(stop_id, route_tag)
  xml_hash = fetch_stop_predictions(stop_id, route_tag)
  dig_predictions(xml_hash)
end

def dig_predictions(xml)
  directions = xml.find_all(&:direction)
  predictions = []
  directions&.each do |direction|
    direction.direction&.find_all(&:prediction)&.each do |x|
      predictions << x.prediction[0].minutes.to_i
    end
  end
  predictions.uniq.sort!
end

def present_doubles(predictions)
  doubles = predictions.each_slice(2).to_a
  doubles.map do | prediction_pair |

    returned = []
    returned.push(prediction_pair.first <= 1 ? 'NOW' : prediction_pair.first.to_s)
    returned.push(prediction_pair[1].to_s) unless prediction_pair.length == 1
    returned.join(', ') unless prediction_pair.length == 1
  end
end

def present_singles(predictions)
  max_predictions_per_route = DEFAULT_MAX_PREDICTIONS_PER_ROUTE
  predictions.map do | minutes |
    case minutes
    when 0
      {text: 'NOW'}
    else
      {text: "#{minutes} MIN"}
    end
  end
end

def serialize_frames(frames, opts = {})
  serialized = frames.each_with_index.map do |x, idx|
    {
      :index => idx,
      :icon => opts.dig(:default_icon) || x.dig(:icon) || ICONS[:LOGO],
      :text => x.class == String && x || x.dig(:text)
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

  bru = [{text: "Oi Bru"}]
  return serialize_frames(bru, default_icon: ICONS[:LOGO])

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
  # presented_predictions = present_singles(crop_predictions(predictions)) # ["NOW", "4 MIN"]
  presented_predictions = present_doubles(crop_predictions(predictions)) # ["NOW, 4"]
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

