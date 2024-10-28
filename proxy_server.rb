require 'sinatra/base'
require 'net/http'
require 'uri'
require 'json'
require 'jwt'
require 'debug'

class ProxyServer < Sinatra::Base

  set :port, 4567

  # Secret key for JWT verification
  SECRET_KEY = 'your-secret-key'

  # Handle CORS headers
  before do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => ['OPTIONS', 'GET', 'POST', 'PUT', 'DELETE'],
            'Access-Control-Allow-Headers' => 'Content-Type, Authorization, x-bump-jwt-token'
  end

  # Verify JWT token presence and signature
  before do
    token = request.env['HTTP_X_BUMP_JWT_TOKEN']

    # Check if token is missing
    if token.nil?
      headers 'Content-Type' => 'application/json'
      halt 401, { error: 'x-bump-jwt-token header is missing' }.to_json
    end

    # Verify JWT token
    begin
      JWT.decode(token, SECRET_KEY, true, { algorithm: 'HS256' })
    rescue JWT::DecodeError
      halt 401, { error: 'Invalid token' }.to_json
    end
  end

  # OPTIONS request for preflight
  options '*' do
    200
  end

  helpers do
    def forward_request(method)
      target_url = params['url']
      uri = URI.parse(target_url)

      # Set up the request to the target server
      target_request = case method
                      when 'GET' then Net::HTTP::Get.new(uri)
                      when 'POST' then Net::HTTP::Post.new(uri)
                      when 'PUT' then Net::HTTP::Put.new(uri)
                      when 'DELETE' then Net::HTTP::Delete.new(uri)
                      end

      # Transfer relevant headers from the client to the target request
      client_headers = request.env.select { |key, _| key.start_with?('HTTP_') }
      client_headers.each do |header, value|
        formatted_header = header.sub('HTTP_', '').split('_').map(&:capitalize).join('-')
        target_request[formatted_header] = value unless formatted_header == 'X-Bump-Jwt-Token'
      end

      # Forward request body for POST and PUT methods
      if %w[POST PUT].include?(method)
        target_request.content_type = request.content_type
        target_request.body = request.body.read
      end

      # Execute the request to the target server
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        response = http.request(target_request)

        # Pass the target server response back to the client
        status response.code
        headers 'Content-Type' => response.content_type
        body response.body
      end
    end
  end

  # Proxy endpoints
  get '/proxy' do
    forward_request('GET')
  end

  post '/proxy' do
    forward_request('POST')
  end

  put '/proxy' do
    forward_request('PUT')
  end

  delete '/proxy' do
    forward_request('DELETE')
  end
end