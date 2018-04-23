# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'

class GooglePlaces
   def initialize(settings_file_path = "settings.yml")
    config = YAML.load_file(settings_file_path) if File.exist?(settings_file_path)
    @places_apikey = ENV['GOOGLE_PLACES_APIKEY'] || config["google_places_api"]
    @endpoint_textsearch = "https://maps.googleapis.com/maps/api/place/textsearch/json?"
    @endpoint_details = "https://maps.googleapis.com/maps/api/place/details/json?"
    @endpoint_photo = "https://maps.googleapis.com/maps/api/place/photo?"
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

  def get_photo_ref(place_info)
    if place_info["status"] != "OK"
      return nil
    end
    photo_ref = place_info["results"][0]["photos"][0]["photo_reference"]

    return photo_ref
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

  def get_place_photo(photo_ref)
    uri = URI(@endpoint_photo)
    res = nil
    uri.query = URI.encode_www_form({
                                      key: @places_apikey,
                                      photoreference: photo_ref,
                                      maxwidth: 400
                                    })
    p uri
    p uri.query
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
    unless place_detail["result"]["opening_hours"].nil?
      open_status = place_detail["result"]["opening_hours"]["open_now"]
      if open_status == true
        open_status = "`営業中`"
      else
        open_status = "`休業`"
      end
    end
    
    unless place_detail["result"]["price_level"].nil?
      price_level = place_detail["result"]["price_level"]
    end
    rating = place_detail["result"]["rating"]
    review = place_detail["result"]["reviews"][0]["text"]
    website = place_detail["result"]["website"]
    
    detail_info = {
      "name" => name,
      "open_status" => open_status,
      "price_level" => price_level,
      "rating" => rating,
      "latest_review" => review,
      "website" => website,
    }

    return detail_info
  end

  def extract_photo_url(html)
    a_tag = html.match(/<A HREF="(.*?)">/)
    photo_url = a_tag[1]
    return photo_url
  end
end

class Response < SlackBot
  # cool code goes here
  # "@Bot「○○」と言って" -> "@user_name ○○"
  def repeat_word(params, options = {})
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
    query_str.match(/「(.*)」の情報/)
    query_str = query_str[1]
    res = googleplaces.get_place_info(query_str)
    place_info = JSON.load(res.body)
    if place_info["status"] != "OK"
      return {text: "結果が取得できませんでした"}.merge(options).to_json
    end
    
    photo_ref = googleplaces.get_photo_ref(place_info)
    
    res = googleplaces.get_place_id(place_info)
    res = googleplaces.get_place_detail(res)
    place_detail = JSON.load(res.body)

    p place_detail
    res = googleplaces.extract_data_from_json(place_detail)
    photo = googleplaces.get_place_photo(photo_ref)
    photo = photo.body # html
    photo = googleplaces.extract_photo_url(photo)

    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    res_text = "#{user_name} \n【 *#{res["name"]}* 】 #{res["open_status"]} \n*価格帯*:moneybag:: #{res["price_level"]}　*評価*:star:: #{res["rating"]}/5　*Webサイト*:computer:: #{res["website"]} \n*最新のレビュー*::information_desk_person: \n#{res["latest_review"]} \n#{photo}"
    
    return {text: res_text}.merge(options).to_json
  end
end

class MySlackBot < SlackBot
  def respond_msg(params, options = {})
    response = Response.new
    if params[:text].include?("と言って")
      response.repeat_word(params, options)
    elsif params[:text].include?("の情報") 
      response.show_place_detail(params, options)
    else
      response.naive_respond(params, options)
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
