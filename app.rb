# frozen_string_literal: true
require 'google/apis/gmail_v1'
require 'google/api_client/client_secrets'
require 'json'
require 'sinatra'
require 'mail'
if settings.development?
  require 'dotenv'
  Dotenv.load('.env', '.env.local')
end

enable :sessions
set :session_secret, ENV['SECRET_TOKEN']
set :haml, format: :html5, escape_html: true
set :views, scss: 'assets', haml: 'views', default: 'views'

helpers do
  def find_template(views, name, engine, &block)
    _, folder = views.detect { |k, _v| engine == Tilt[k] }
    folder ||= views[:default]
    super(folder, name, engine, &block)
  end
end

CLIENT_SETTINGS = {
  client_id: ENV['GOOGLE_CLIENT_ID'],
  client_secret: ENV['GOOGLE_CLIENT_SECRET'],
  auth_uri: ENV['GOOGLE_AUTH_URI'],
  token_uri: ENV['GOOGLE_TOKEN_URI'],
  redirect_uri: ENV['GOOGLE_REDIRECT_URI']
}.freeze
CLIENT_SECRETS = Google::APIClient::ClientSecrets.new(web: CLIENT_SETTINGS)

# Add some utilities to Time instances.
class Time
  def week
    strftime('%U').to_i
  end

  def relativize
    now = Time.now
    if now.year > year
      ''
    elsif now.month > month && now.week > week
      'this year'
    elsif now.week > week
      'this month'
    elsif now.mday > mday
      'this week'
    else
      'today'
    end
  end
end

# Add some utilities to Thread instances.
class Google::Apis::GmailV1::Thread
  def subject
    messages[0].subject
  end

  def from
    from_raw = messages[0].from
    from = Mail::Address.new(from_raw)
    from.display_name || from.address
  end

  def snippet
    messages[0].snippet
  end

  def date
    messages[0].date
  end

  def haml_object_ref
    'thread'
  end

  def mark_unread_url
    "/unread/#{id}"
  end

  def archive_url
    "/archive/#{id}"
  end
end

# Add some utilities to Message instances.
class Google::Apis::GmailV1::Message
  def subject
    payload.headers.find { |h| h.name == 'Subject' }.value
  end

  def from
    payload.headers.find { |h| h.name == 'From' }.value
  end

  def date
    sent = Time.at(internal_date.to_i / 1000)
    sent.relativize
  end

  def render_url
    "/render/#{id}"
  end

  def haml_object_ref
    'message'
  end
end

get '/' do
  haml :index
end

get '/style.css' do
  last_modified File.mtime('assets/style.scss')
  scss :style, style: :expanded
end

get '/oauth2callback' do
  auth_client = CLIENT_SECRETS.to_authorization
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
  begin
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    gmail = Google::Apis::GmailV1::GmailService.new
    opts = { authorization: auth_client }
    list = gmail.list_user_threads('me', label_ids: 'INBOX', options: opts)
    @remaining = list.result_size_estimate
    @remaining = '~' + @remaining.to_s if @remaining > list.threads.length
    threads = list.threads.sample(2)
    @threads = threads.map do |t|
      gmail.get_user_thread('me', t.id, format: 'metadata', options: opts)
    end
    haml :cull
  rescue ArgumentError => e
    raise unless e.message == 'Missing authorization code.'
    redirect to('/oauth2callback')
  rescue Signet::AuthorizationError
    redirect to('/oauth2callback')
  end
end

get '/render/:msg' do |msg_id|
  redirect to('/oauth2callback') unless session.key?(:credentials)
  begin
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    gmail = Google::Apis::GmailV1::GmailService.new
    opts = { authorization: auth_client }
    message = gmail.get_user_message('me', msg_id, format: 'raw', options: opts)
    message = Mail.read_from_string(message.raw)
    if message.multipart?
      message.html_part.decoded
    else
      headers \
        'Content-Type' => message.content_type || 'text/plain'
      message.body.decoded
    end
  rescue ArgumentError => e
    raise unless e.message == 'Missing authorization code.'
    redirect to('/oauth2callback')
  rescue Signet::AuthorizationError
    redirect to('/oauth2callback')
  end
end

post '/unread/:thread' do |thread_id|
  redirect to('/oauth2callback') unless session.key?(:credentials)
  begin
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    gmail = Google::Apis::GmailV1::GmailService.new
    opts = { authorization: auth_client }
    request = Google::Apis::GmailV1::ModifyThreadRequest.new
    request.update!(add_label_ids: ['UNREAD'])
    gmail.modify_thread('me', thread_id, request, options: opts)
    redirect to('/cull')
  rescue ArgumentError => e
    raise unless e.message == 'Missing authorization code.'
    redirect to('/oauth2callback')
  rescue Signet::AuthorizationError
    redirect to('/oauth2callback')
  end
end

post '/archive/:thread' do |thread_id|
  redirect to('/oauth2callback') unless session.key?(:credentials)
  begin
    client_opts = JSON.parse(session[:credentials])
    auth_client = Signet::OAuth2::Client.new(client_opts)
    gmail = Google::Apis::GmailV1::GmailService.new
    opts = { authorization: auth_client }
    request = Google::Apis::GmailV1::ModifyThreadRequest.new
    request.update!(remove_label_ids: %w(UNREAD INBOX))
    gmail.modify_thread('me', thread_id, request, options: opts)
    redirect to('/cull')
  rescue ArgumentError => e
    raise unless e.message == 'Missing authorization code.'
    redirect to('/oauth2callback')
  rescue Signet::AuthorizationError
    redirect to('/oauth2callback')
  end
end
