# frozen_string_literal: true
require 'google/apis/gmail_v1'
require 'google/api_client/client_secrets'
require 'json'
require 'sinatra'
require 'mail'

enable :sessions
set :session_secret, 'sample text' if settings.development?
set :haml, format: :html5, escape_html: true
set :views, scss: 'assets', haml: 'views', default: 'views'

helpers do
  def find_template(views, name, engine, &block)
    _, folder = views.detect { |k, _v| engine == Tilt[k] }
    folder ||= views[:default]
    super(folder, name, engine, &block)
  end
end

# Add some utilities to Thread instances.
class Google::Apis::GmailV1::Thread
  public
  def subject
    messages[0].payload.headers.find { |h| h.name == 'Subject' }.value
  end
  
  def from
    from_raw = messages[0].payload.headers.find { |h| h.name == 'From' }.value
    from = Mail::Address.new(from_raw)
    from.display_name || from.address
  end
  
  def snippet
    messages[0].snippet
  end
  
  def haml_object_ref
    "thread"
  end
end

get '/' do
  haml :index
end

get '/style.css' do
  scss :style, style: :expanded
end

get '/oauth2callback' do
  client_secrets = Google::APIClient::ClientSecrets.load
  auth_client = client_secrets.to_authorization
  auth_client.update!(
    scope: 'https://mail.google.com/',
    redirect_uri: url('/oauth2callback')
  )
  if request['code'].nil?
    auth_uri = auth_client.authorization_uri.to_s
    redirect to(auth_uri)
  else
    auth_client.code = request['code']
    auth_client.fetch_access_token!
    auth_client.client_secret = nil
    session[:credentials] = auth_client.to_json
    redirect to('/cull')
  end
end

get '/logout' do
  session[:credentials] = nil
  redirect to('/')
end

get '/cull' do
  redirect to('/oauth2callback') unless session.key?(:credentials)
  client_opts = JSON.parse(session[:credentials])
  auth_client = Signet::OAuth2::Client.new(client_opts)
  gmail = Google::Apis::GmailV1::GmailService.new
  opts = { authorization: auth_client }
  threads = gmail.list_user_threads('me', label_ids: 'INBOX',
                                          options: opts).threads
  threads = threads.sample(2)
  @threads = threads.map { |t| gmail.get_user_thread('me', t.id, options: opts) }
  haml :cull
end
