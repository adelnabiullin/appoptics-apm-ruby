# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require "minitest_helper"
require 'mocha/minitest'

require_relative '../jobs/sidekiq/activejob_worker_job'
require_relative '../servers/sidekiq_activejob.rb'

Sidekiq.configure_server do |config|
  config.redis = { :password => 'secret_pass' }
end

describe "RailsSharedTests" do
  before do
    clear_all_traces
    AppOpticsAPM.config_lock.synchronize {
      @tm = AppOpticsAPM::Config[:tracing_mode]
      @sample_rate = AppOpticsAPM::Config[:sample_rate]
    }
  end

  after do
    AppOpticsAPM.config_lock.synchronize {
      AppOpticsAPM::Config[:tracing_mode] = @tm
      AppOpticsAPM::Config[:sample_rate] = @sample_rate
    }
  end

  it "should NOT trace when tracing is set to :never" do
    AppOpticsAPM.config_lock.synchronize do
      AppOpticsAPM::Config[:tracing_mode] = :never
      uri = URI.parse('http://127.0.0.1:8140/hello/world')
      r = Net::HTTP.get_response(uri)

      traces = get_all_traces
      traces.count.must_equal 0
    end
  end

  it "should NOT trace when sample_rate is 0" do
    AppOpticsAPM.config_lock.synchronize do
      AppOpticsAPM::Config[:sample_rate] = 0
      uri = URI.parse('http://127.0.0.1:8140/hello/world')
      r = Net::HTTP.get_response(uri)

      traces = get_all_traces
      traces.count.must_equal 0
    end
  end

  it "should NOT trace when there is no context" do
    response_headers = HelloController.action("world").call(
        "REQUEST_METHOD" => "GET",
        "rack.input" => -> {}
    )[1]

    response_headers.key?('X-Trace').must_equal false

    traces = get_all_traces
    traces.count.must_equal 0
  end

  it "should send inbound metrics" do
    test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil

    AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
      test_action = action
      test_url = url
      test_status = status
      test_method = method
      test_error = error
    end.once

    uri = URI.parse('http://127.0.0.1:8140/hello/world')
    Net::HTTP.get_response(uri)

    assert_equal "HelloController.world", test_action
    assert_equal "http://127.0.0.1:8140/hello/world", test_url
    assert_equal 200, test_status
    assert_equal "GET", test_method
    assert_equal 0, test_error

    assert_controller_action(test_action)
  end

  it "should send inbound metrics when not tracing" do
    test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
    AppOpticsAPM.config_lock.synchronize do
      AppOpticsAPM::Config[:tracing_mode] = :never
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      uri = URI.parse('http://127.0.0.1:8140/hello/world')
      Net::HTTP.get_response(uri)
    end

    assert_equal "HelloController.world", test_action
    assert_equal "http://127.0.0.1:8140/hello/world", test_url
    assert_equal 200, test_status
    assert_equal "GET", test_method
    assert_equal 0, test_error
  end

  it "should send metrics for 500 errors" do
    test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil

    AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
      test_action = action
      test_url = url
      test_status = status
      test_method = method
      test_error = error
    end.once

    uri = URI.parse('http://127.0.0.1:8140/hello/servererror')
    Net::HTTP.get_response(uri)

    assert_equal "HelloController.servererror", test_action
    assert_equal "http://127.0.0.1:8140/hello/servererror", test_url
    assert_equal 500, test_status
    assert_equal "GET", test_method
    assert_equal 1, test_error

    assert_controller_action(test_action)
  end

  it "should find the controller action for a route with a parameter" do
    test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil

    AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
      test_action = action
      test_url = url
      test_status = status
      test_method = method
      test_error = error
    end.once

    uri = URI.parse('http://127.0.0.1:8140/hello/15/show')
    Net::HTTP.get_response(uri)

    assert_equal "HelloController.show", test_action
    assert_equal "http://127.0.0.1:8140/hello/15/show", test_url
    assert_equal 200, test_status
    assert_equal "GET", test_method
    assert_equal 0, test_error

    assert_controller_action(test_action)
  end

  it "should find controller action in the metal stack" do
    test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil

    AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
      test_action = action
      test_url = url
      test_status = status
      test_method = method
      test_error = error
    end.once

    uri = URI.parse('http://127.0.0.1:8140/hello/metal')
    r = Net::HTTP.get_response(uri)

    assert_equal 200, test_status
    assert_equal "FerroController.world", test_action
    assert_equal "http://127.0.0.1:8140/hello/metal", test_url
    assert_equal "GET", test_method
    assert_equal 0, test_error

    assert_controller_action(test_action)
  end

  it "should use wrapped class for ActiveJobs" do
    skip unless defined?(ActiveJob)
    AppOpticsAPM::API.start_trace('test_trace') do
      ActiveJobWorkerJob.perform_later
    end

    # Allow the job to be run
    sleep 5

    traces = get_all_traces

    sidekiq_traces = traces.select { |tr| tr['Layer'] =~ /sidekiq/ }
    assert_equal 4, sidekiq_traces.count, "count sidekiq traces"
    assert sidekiq_traces.find { |tr| tr['Layer'] == 'sidekiq-client' && tr['JobName'] == 'ActiveJobWorkerJob' }
    assert sidekiq_traces.find { |tr| tr['Layer'] == 'sidekiq-worker' && tr['JobName'] == 'ActiveJobWorkerJob' }
    assert sidekiq_traces.find { |tr| tr['Layer'] == 'sidekiq-worker' && tr['Action'] == 'ActiveJobWorkerJob' }

  end

end
