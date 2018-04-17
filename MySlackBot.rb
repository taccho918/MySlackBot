# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'

class GooglePlaces
   def initialize(settings_file_path = "settings.yml")
    config = YAML.load_file(settings_file_path) if File.exist?(settings_file_path)
    @places_apikey = config["google_places_api"]
    @endpoint_textsearch = "https://maps.googleapis.com/maps/api/place/textsearch/json?"
    @endpoint_details = "https://maps.googleapis.com/maps/api/place/details/json?"
  end

  # get place info by text search 
  def get_place_info(keyword)
    uri = URI(@endpoint_textsearch)
    res = nil
    uri.query = URI.encode_www_form({
                                      language: "ja",
                                      query: keyword,
                                      key: @places_apikey
                                    })
    p uri.query
    p uri
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.get(uri)
    end

    return res
  end

  def get_place_id(place_info)
    if place_info["status"] != "OK"
      return nil
    end
    place_id = place_info["results"][0]["place_id"]

    return place_id
  end
  
  # get place detail by place id given by text search
  def get_place_detail(place_id)
    uri = URI(@endpoint_details)
    res = nil
    uri.query = URI.encode_www_form({
                                      language: "ja",
                                      place_id: place_id,
                                      key: @places_apikey
                                    })
    p uri
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.get(uri)
    end

    return res
  end

  def extract_data_from_json(place_detail)
    if place_detail["status"] != "OK"
      return nil
    end

    name = place_detail["result"]["name"]
    rating = place_detail["result"]["rating"]
    website = place_detail["result"]["website"]
    detail_info = {
      "name" => name,
      "rating" => rating,
      "website" => website
    }

    return detail_info
  end
end

class Response < SlackBot
  # cool code goes here
  # "@Bot「○○」と言って" -> "@user_name ○○"
  def repeat_word(params, options = {})
    return nil if params[:user_name] == "slackbot" || params[:user_id] == "USLACKBOT"

    msg = params[:text]
    msg = msg.match(/「(.*)」と言って/)
    msg = msg[1]
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    return {text: "#{user_name} #{msg}"}.merge(options).to_json
  end

  # show detail info about certain place
  def show_place_detail(params, options = {})
    googleplaces = GooglePlaces.new

    query_str = params[:text]
    query_str.slice!("@TakaBot ")
    res = googleplaces.get_place_info(query_str)
    place_info = JSON.load(res.body)
    
    res = googleplaces.get_place_id(place_info)
    p place_info["results"][0]["place_id"]
    
    res = googleplaces.get_place_detail(res)
    place_detail = JSON.load(res.body)
    res = googleplaces.extract_data_from_json(place_detail)

    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    res_text = "#{user_name} #{res["name"]}: #{res["rating"]}, #{res["website"]}"
    
    return {text: res_text}.merge(options).to_json
  end
end

class MySlackBot < SlackBot
  def respond_msg(params, options = {})
    response = Response.new
    if params[:text].include?("と言って") then
      response.repeat_word(params, options)
    else
      response.show_place_detail(params, options)
    end
  end
end

slackbot = MySlackBot.new

set :environment, :production

get '/' do
  "SlackBot Server"
end

post '/slack' do
  content_type :json
  
  slackbot.respond_msg(params, {username: "TakaBot", link_names: true})
end
