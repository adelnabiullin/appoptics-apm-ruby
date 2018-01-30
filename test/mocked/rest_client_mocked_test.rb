# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

unless defined?(JRUBY_VERSION)
  require 'minitest_helper'
  require 'webmock/minitest'
  require 'mocha/mini_test'
  WebMock.allow_net_connect!

  class RestClientMockedTest < Minitest::Test

    def setup
      WebMock.enable!
      WebMock.disable_net_connect!
      AppOpticsAPM.config_lock.synchronize do
        @sample_rate = AppOpticsAPM::Config[:sample_rate]
      end
    end

    def teardown
      AppOpticsAPM.config_lock.synchronize do
        AppOpticsAPM::Config[:sample_rate] = @sample_rate
        AppOpticsAPM::Config[:blacklist] = []
      end
      WebMock.reset!
      WebMock.allow_net_connect!
      WebMock.disable!
    end

    def test_tracing_sampling
      stub_request(:get, "http://127.0.0.1:8101/").to_return(status: 200, body: "", headers: {})

      AppOpticsAPM::API.start_trace('rest_client_tests') do
        RestClient::Resource.new('http://127.0.0.1:8101').get
      end

      assert_requested :get, "http://127.0.0.1:8101/", headers: {'X-Trace'=>/^2B[0-9,A-F]*01$/}, times: 1
    end

    def test_tracing_not_sampling
      stub_request(:get, "http://127.0.0.2:8101/").to_return(status: 200, body: "", headers: {})

      AppOpticsAPM.config_lock.synchronize do
        AppOpticsAPM::Config[:sample_rate] = 0
        AppOpticsAPM::API.start_trace('rest_client_tests') do
          RestClient::Resource.new('http://127.0.0.2:8101').get
        end
      end

      assert_requested :get, "http://127.0.0.2:8101/", headers: {'X-Trace'=>/^2B[0-9,A-F]*00$/}, times: 1
      assert_not_requested :get, "http://127.0.0.2:8101/", headers: {'X-Trace'=>/^2B0*$/}
    end

    def test_no_xtrace
      stub_request(:get, "http://127.0.0.3:8101/").to_return(status: 200, body: "", headers: {})

      RestClient::Resource.new('http://127.0.0.3:8101').get

      assert_requested :get, "http://127.0.0.3:8101/", times: 1
      assert_not_requested :get, "http://127.0.0.3:8101/", headers: {'X-Trace'=>/^.*$/}
    end

    def test_blacklisted
      stub_request(:get, "http://127.0.0.4:8101/").to_return(status: 200, body: "", headers: {})

      AppOpticsAPM.config_lock.synchronize do
        AppOpticsAPM::Config.blacklist << '127.0.0.4'
        AppOpticsAPM::API.start_trace('rest_client_tests') do
          RestClient::Resource.new('http://127.0.0.4:8101').get
        end
      end

      assert_requested :get, "http://127.0.0.4:8101/", times: 1
      assert_not_requested :get, "http://127.0.0.4:8101/", headers: {'X-Trace'=>/^.*$/}
    end

    def test_not_sampling_blacklisted
      stub_request(:get, "http://127.0.0.5:8101/").to_return(status: 200, body: "", headers: {})

      AppOpticsAPM.config_lock.synchronize do
        AppOpticsAPM::Config[:sample_rate] = 0
        AppOpticsAPM::Config.blacklist << '127.0.0.5'
        AppOpticsAPM::API.start_trace('rest_client_tests') do
          RestClient::Resource.new('http://127.0.0.5:8101').get
        end
      end

      assert_requested :get, "http://127.0.0.5:8101/", times: 1
      assert_not_requested :get, "http://127.0.0.5:8101/", headers: {'X-Trace'=>/^.*$/}
    end

  end
end