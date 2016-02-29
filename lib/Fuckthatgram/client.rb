module Fuckthatgram
  class ClientException < Exception; end

  class Client
    def initialize(username, password, debug = false, ig_data_path = nil)
      @is_logged_in = false
      @user = {}

      @username  = username
      @password  = password
      @debug     = debug
      @uuid      = generate_UUID(true)
      @device_id = generate_device_id

      if ig_data_path
        @ig_data_path = ig_data_path
      else
        @ig_data_path = "/tmp/fuckthatgram/"
      end

      if File.exists?("#{@ig_data_path}#{@username}.dat")
        @is_logged_in = true
        @user = JSON.parse(File.read("#{@ig_data_path}#{@username}.dat"),
                          :symbolize_names => true)
        @rank_token = "#{@user[:username_id]}_#{@uuid}"
        @token = @user[:cookie].split('csrftoken=').last.split(";").first
      end
    end

    def login
      log "login"
      if !@is_logged_in
        resp = request('si/fetch_headers/', params: {
                  challenge_type: 'signup',
                  guid: generate_UUID(false)
                }, login: true)

        @user[:cookie] = resp['set-cookie']
        @token = resp['set-cookie'].split('csrftoken=').last.split(";").first

        data = {
          'device_id' => @device_id,
          'guid'      => @uuid,
          'phone_id'  => generate_UUID(true),
          'username'  => @username,
          'password'  => @password,
          'login_attempt_count' => '0'
        }
        resp = request('accounts/login/', post: generate_signature(data.to_json), login: true)
        @user[:cookie] = resp['set-cookie']

        if resp.body[:status] == 'fail'
          raise ClientException, resp.body[:message]
        end

        @is_logged_in = true
        @user[:username_id] = resp.body[:logged_in_user][:pk]
        @user[:name] = resp.body[:logged_in_user][:full_name]
        @rank_token = "#{@user[:username_id]}_#{@uuid}"
        @token = @user[:cookie].split('csrftoken=').last.split(";").first

        Dir.mkdir(@ig_data_path) if !File.directory?(@ig_data_path)
        File.open("#{@ig_data_path}#{@username}.dat", "w") do |f|
          f.write(@user.to_json)
        end

        sync_features
        auto_complete_user_list
        timeline_feed
        get_v2_inbox
        get_recent_activity

      else
        timeline_feed
        get_v2_inbox
        get_recent_activity
      end
    end

    def sync_features
      log "sync_features"
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        'id' => @user[:username_id], '_csrftoken' => @token,
        'experiments' => Constants::EXPERIMENTS
      }
      request("qe/sync/", post: generate_signature(data.to_json))
    end

    def auto_complete_user_list
      log "auto_complete_user_list"
      request("friendships/autocomplete_user_list/")
    end

    def timeline_feed
      log "timeline_feed"
      request("feed/timeline/")
    end

    def megaphone_log
      log "megaphone_log"
      request("megaphone/log/")
    end

    def expose
      log "expose"
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        'id' => @user[:username_id], '_csrftoken' => @token,
        'experiments' => 'ig_android_profile_contextual_feed'
      }
      request("qe/expose/", post: generate_signature(data.to_json))
    end

    def logout
      log "logout"
      resp = request('accounts/logout/')
      if resp.body == 'ok'
        true
      else
        false
      end
    end

    def upload_photo(photo, caption = nil)
      log "upload_photo"

      if photo.start_with?('http') || File.exists?(photo)
        file = open(photo)
      else
        raise ClientException, "Picture not found at:\n#{photo}"
      end

      uri = URI(Constants::API_URL + 'upload/photo/')
      bodies = [
        {
  				type: 'form-data',
  				name: 'upload_id',
  				data: (Time.now.to_f * 1000.0).to_i
  			},
  			{
  				type: 'form-data',
  				name: '_uuid',
  				data: @uuid
  			},
  			{
  				type: 'form-data',
  				name: '_csrftoken',
  				data: @token
  			},
  			{
  				type: "form-data",
  				name: "image_compression",
  			  data: '{"lib_name":"jt","lib_version":"1.3.0","quality":"70"}'
  			},
  			{
  				type: 'form-data',
  				name: 'photo',
  				data: file.read,
  				filename: "pending_media_#{(Time.now.to_f * 1000.0).to_i}.jpg",
  				headers: {
            'Content-Transfer-Encoding' => 'binary',
  					'Content-type' => 'application/octet-stream'
  				}
  			}
      ]

      data = build_body(bodies, @uuid)

      headers = {
        'Connection' => 'close',
        'Accept' => '*/*',
        'Content-type' => "multipart/form-data; boundary=#{@uuid}",
        'Cookie2' => '$Version=1',
        'Content-Length' => "#{file.size}",
        'User-Agent' => Fuckthatgram::Constants::USER_AGENT,
        'Accept-Language' => 'en-US',
        'Accept-Encoding' => 'gzip'
      }
      headers['Cookie'] = @user[:cookie] if @user[:cookie]

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      resp = http.post(uri.path, data, headers)
      resp.body = JSON.parse(resp.body || "{}", :symbolize_names => true)

      if resp.body[:status] == 'fail'
        raise ClientException, resp.body[:message]
      end

      log_resp resp, uri

      configure_photo = configure(resp.body[:upload_id], photo, caption)
      expose

      configure_photo
    end

    def configure(upload_id, photo, caption = '')
      size = FastImage.size(photo)

      data = {
        upload_id: upload_id,
        camera_model: 'HM1S',
        source_type: 3,
        data_time_original: Time.new.strftime("%Y:%m:%d %H:%i:%s"),
        camera_make: 'XIAOMI',
        edits: {
          crop_original_size: size,
          crop_zoom: 1.3333334,
          crop_center: [0.0, -0.0],
        },
        extra: {
          source_width: size[0],
          source_height: size[1]
        },
        device: {
          manufacturer: 'Xiaomi',
          model: "HM 1SW",
          android_version: 18,
          android_release: "4.3"
        },
        '_csrftoken' => @token,
        '_uuid' => @uuid,
        '_uid' => @user[:username_id],
        caption: caption
      }.to_json.gsub('"crop_center":[0,0]', '"crop_center":[0.0,-0.0]')

      request('media/configure/', post: generate_signature(data))
    end

    def edit_media media_id, caption_text
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, caption_text: caption_text
      }
      request("media/#{media_id}/edit_media/", post: generate_signature(data))
    end

    def media_info media_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, media_id: media_id
      }
      request("media/#{media_id}/info/", post: generate_signature(data))
    end

    def delete_media media_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, media_id: media_id
      }
      request("media/#{media_id}/delete/", post: generate_signature(data))
    end

    def comment media_id, comment_text
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, comment_text: comment_text
      }
      request("media/#{media_id}/comment/", post: generate_signature(data))
    end

    def change_profile_picture
    end

    def remove_profile_picture
    end

    def set_account_private
    end

    def set_account_public
    end

    def get_profile_data
      # nope!
      request('accounts/current_user/', params: {edit: true}, post: generate_signature())
    end

    def edit_profile
    end

    def get_username_info username_id
      request("users/#{username_id}/info/")
    end

    def get_my_info
      get_username_info(@user[:username_id])
    end

    def get_recent_activity
      log "get_recent_activity"
      resp = request("news/inbox/?")
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      return resp
    end

    def get_v2_inbox
      log "get_v2_inbox"
      resp = request("direct_v2/inbox/?")
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      return resp
    end

    def get_user_tags username_id
      resp = request("usertags/#{username_id}/feed/", params: {rank_token: @rank_token, ranked_content: true} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_my_tags
      get_user_tags(@user[:username_id])
    end

    def tag_feed tag
      resp = request("feed/tag/#{tag}/", params: {rank_token: @rank_token, ranked_content: true} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_media_likers media_id
      resp = request("media/#{media_id}/likers/?")
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_geo_media username_id
      resp = request("maps/user/#{username_id}")
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_my_geo_media
      get_geo_media(@user[:username_id])
    end

    def fb_user_search query
      resp = request("fbsearch/topsearch/", params: {context: "blended", query: query, rank_token: @rank_token} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def search_users query
      resp = request("users/search/", params: {ig_sig_key_version: Constants::SIG_KEY_VERSION, is_typeahead: true, query: query, rank_token: @rank_token} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def sync_from_adress_book
    end

    def search_tags query
      resp = request("tags/search/", params: {is_typeahead: true, q: query, rank_token: @rank_token} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_timeline
      resp = request("feed/timeline/", params: {rank_token: @rank_token, ranked_content: true} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_user_feed username_id
      resp = request("feed/user/#{username_id}/", params: {rank_token: @rank_token, ranked_content: true} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_my_feed
      get_user_feed(@user[:username_id])
    end

    def get_popular_feed
      resp = request("feed/popular/", params: {people_teaser_supported: 1, rank_token: @rank_token, ranked_content: true} )
      if resp.body[:status] != 'ok'
        raise ClientException, resp.body[:message]
      end
      resp.body
    end

    def get_user_followings username_id, max_id = nil
      resp = request("friendships/#{username_id}/following/", params: {max_id: max_id, ig_sig_key_version: Constants::SIG_KEY_VERSION, rank_token: @rank_token} )
      resp.body
    end

    def get_user_followers username_id, max_id = nil
      resp = request("friendships/#{username_id}/followers/", params: {max_id: max_id, ig_sig_key_version: Constants::SIG_KEY_VERSION, rank_token: @rank_token} )
      resp.body
    end

    def get_my_followers
      get_user_followers(@user[:username_id])
    end

    def get_my_following
      request("friendship/following", params: {ig_sig_key_version: Constants::SIG_KEY_VERSION, rank_token: @rank_token} )
    end

    def like media_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, media_id: media_id
      }
      request("media/#{media_id}/like/", post: generate_signature(data))
    end

    def unlike media_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, media_id: media_id
      }
      request("media/#{media_id}/unlike/", post: generate_signature(data))
    end

    def get_media_comments media_id
      request("media/#{media_id}/comments/?")
    end

    def set_name_and_phone name = "", phone = ""
    end

    def get_direct_share
      request("direct_share/inbox/?")
    end

    def follow username_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, user_id: username_id
      }
      request("friendships/create/#{username_id}/", post: generate_signature(data))
    end

    def unfollow username_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, user_id: username_id
      }
      request("friendships/destroy/#{username_id}/", post: generate_signature(data))
    end

    def block username_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, user_id: username_id
      }
      request("friendships/block/#{username_id}/", post: generate_signature(data))
    end

    def unblock username_id
      data = {
        '_uuid' => @uuid, '_uid' => @user[:username_id],
        '_csrftoken' => @token, user_id: username_id
      }
      request("friendships/unblock/#{username_id}/", post: generate_signature(data))
    end

    def get_liked_media
      request("feed/liked/?")
    end

    private

    def build_body(bodies, boundary)
      body = ""
      bodies.each do |b|
        body += "--#{boundary}\r\n"
        body += "Content-Disposition: #{b[:type]}; name=\"#{b[:name]}\""

        if b[:filename]
          ext   = b[:filename].split(".").last
          body += "; filename=\"pending_media_#{(Time.now.to_f * 1000.0).to_i}.#{ext}\""
        end

        if b[:headers]
          b[:headers].each do |k,v|
            body += "\r\n#{k}: #{v}"
          end
        end

        body += "\r\n\r\n#{b[:data]}\r\n"
      end
      body += "--#{boundary}--"
      body
    end

    def generate_device_id
      log "generate_device_id"
      "android-#{Digest::MD5.hexdigest("#{rand(99999)}.#{rand(99999)}")[0..15]}"
    end

    def generate_signature(data)
      log "generate_signature"
      hash = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), Constants::IG_SIG_KEY, data)
      "ig_sig_key_version=#{Constants::SIG_KEY_VERSION}&signed_body=#{hash}.#{URI.escape(data)}"
    end

    def generate_UUID(type)
      log "generate_UUID"
      uuid = sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
                     rand(0..0xffff), rand(0..0xffff), rand(0..0xffff),
                     rand(0..0xffff) | 0x4000, rand(0..0x3fff) | 0x8000,
                     rand(0..0xffff), rand(0..0xffff), rand(0..0xffff))
      type ? uuid : uuid.gsub('-','')
    end

    def request(endpoint, options = {})
      options = {
        params: {},
        post: nil,
        login: false
      }.merge(options)

      if !@is_logged_in && !options[:login]
        raise ClientException, "Not logged in"
      end

      uri =  "#{Constants::API_URL}#{endpoint}"
      uri += "?".concat(options[:params].collect{ |k,v|
               "#{k}=#{CGI::escape(v.to_s)}"
             }.join('&'))
      uri = URI(uri.chomp("?"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      headers = {
        'Connection' => 'close',
        'Accept' => '*/*',
        'Content-type' => 'application/x-www-form-urlencoded; charset=UTF-8',
        'Cookie2' => '$Version=1',
        'Accept-Language' => 'en-US',
        'User-Agent' => Fuckthatgram::Constants::USER_AGENT
      }
      headers['Cookie'] = @user[:cookie] if @user[:cookie]

      if options[:post]
        resp = http.post(uri.path, options[:post], headers)
      else
        resp = http.get(uri.request_uri, headers)
      end

      @user[:cookie] = resp['set-cookie'] if resp['set-cookie'] && resp['set-cookie'].include?('ds_user=')

      log_resp resp, uri, options

      resp.body = JSON.parse(resp.body || "{}", :symbolize_names => true)
      resp
    end

    def log string
      puts ":: #{string}" if @debug
    end

    def log_resp resp, uri, options = {}
      if @debug
        puts "#{'-'*30}\n#{(options[:post].nil? ? 'GET' : 'POST')}: #{uri.host}:#{uri.port}#{uri.request_uri}"
        if options[:post]
          puts "> #{options[:post]}"
        end
        resp.each do |key,val|
          puts "- #{key} = #{val}"
        end
        puts "BODY:"
        puts resp.body
        puts ""
      end
    end

  end
end
