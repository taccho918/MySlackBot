# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'

class MySlackBot < SlackBot
  # cool code goes here
  # "@Bot「○○」と言って" -> "@user_name ○○"
  def respond_msg(params, options = {})
    return nil if params[:user_name] == "slackbot" || params[:user_id] == "USLACKBOT"

    msg = params[:text]
    msg = msg.match(/「(.*)」と言って/)
    msg = msg[1]
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    return {text: "#{user_name} #{msg}"}.merge(options).to_json
  end  
end

slackbot = MySlackBot.new

set :environment, :production

get '/' do
  "SlackBot Server"
end

post '/slack' do
  content_type :json
  
  # slackbot.naive_respond(params, username: "TakaBot")
  slackbot.respond_msg(params, username: "TakaBot")
end
