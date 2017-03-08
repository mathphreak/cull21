# frozen_string_literal: true
require 'google/apis/gmail_v1'
require 'google/api_client/client_secrets'
require 'json'
require 'sinatra'

enable :sessions
set :session_secret, 'sample_text'

# This contains the extensions that I'm using to the Google API client.
module GAPIExtensions
  refine Google::Apis::GmailV1::Thread do
    def subject
      messages[0].payload.headers.find { |h| h.name == 'Subject' }.value
    end
  end
end

using GAPIExtensions

get '/' do
  redirect to('/oauth2callback') unless session.key?(:credentials)
  client_opts = JSON.parse(session[:credentials])
  auth_client = Signet::OAuth2::Client.new(client_opts)
  gmail = Google::Apis::GmailV1::GmailService.new
  opts = { authorization: auth_client }
  threads = gmail.list_user_threads('me', label_ids: 'UNREAD', max_results: 10,
                                          options: opts).threads
  threads = threads.map { |t| gmail.get_user_thread('me', t.id, options: opts) }
  subjects = threads.map(&:subject)
  "<pre>#{JSON.pretty_generate(subjects)}</pre>"
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
    redirect to('/')
  end
end
