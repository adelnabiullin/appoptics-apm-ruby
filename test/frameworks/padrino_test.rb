# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require "minitest_helper"
require "mocha/minitest"

if defined?(::Padrino)
  require File.expand_path(File.dirname(__FILE__) + '/apps/padrino_simple')

  describe Padrino do
    before do
      clear_all_traces
      @bt = AppOpticsAPM::Config[:padrino][:collect_backtraces]
    end

    after do
      AppOpticsAPM::Config[:padrino][:collect_backtraces] = @bt
    end

    it "should trace a request to a simple padrino stack" do
      @app = SimpleDemo

      r = get "/render"

      traces = get_all_traces

      traces.count.must_equal 8
      valid_edges?(traces).must_equal true
      validate_outer_layers(traces, 'rack')

      traces[1]['Layer'].must_equal "padrino"
      traces[6]['Controller'].must_equal "SimpleDemo"
      traces[7]['Label'].must_equal "exit"

      layer_has_key_once(traces, 'padrino', 'Backtrace')

      # Validate the existence of the response header
      r.headers.key?('X-Trace').must_equal true
      r.headers['X-Trace'].must_equal traces[7]['X-Trace']
    end

    it "should log an error on exception" do
      @app = SimpleDemo

      SimpleDemo.any_instance.expects(:dispatch_without_appoptics).raises(StandardError)

      begin
        r = get "/render"
      rescue
      end

      traces = get_all_traces
      traces.count.must_equal 5
      valid_edges?(traces).must_equal true
      validate_outer_layers(traces, 'rack')

      traces[2]['Layer'].must_equal "padrino"

      error_traces = traces.select{ |trace| trace['Label'] == 'error' }
      error_traces.size.must_equal 1

      error_trace = error_traces[0]
      error_trace['Layer'].must_equal 'padrino'
      error_trace['Spec'].must_equal 'error'
      error_trace.key?('ErrorClass').must_equal true
      error_trace.key?('ErrorMsg').must_equal true
    end

    it 'should not report backtraces' do
      AppOpticsAPM::Config[:padrino][:collect_backtraces] = false
      @app = SimpleDemo

      r = get "/render"

      traces = get_all_traces

      layer_doesnt_have_key(traces, 'padrino', 'Backtrace')
    end


    it "should report controller.action" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      get "/render"

      assert_equal "SimpleDemo./render", test_action
      assert_equal "http://example.org/render", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should report controller.action for a symbol route" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      get "/symbol_route"

      assert_equal "SimpleDemo./symbol_route", test_action
      assert_equal "http://example.org/symbol_route", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should report controller.action with :id" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      r = get "/render/1234567890"

      r.body.must_match /1234567890/

      assert_equal "SimpleDemo./render/:id", test_action
      assert_equal "http://example.org/render/1234567890", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should report controller.action for a symbol route with :id" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      r = get "/symbol_route/1234567890"

      r.body.must_match /1234567890/

      assert_equal "SimpleDemo./symbol_route/:id", test_action
      assert_equal "http://example.org/symbol_route/1234567890", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should report controller.action with :id and more" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      r = get "/render/1234567890/what"

      r.body.must_match /WOOT is 1234567890/

      assert_equal "SimpleDemo./render/:id/what", test_action
      assert_equal "http://example.org/render/1234567890/what", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should report an error" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      get "/error"

      assert_equal "SimpleDemo./error", test_action
      assert_equal "http://example.org/error", test_url
      assert_equal 500, test_status
      assert_equal "GET", test_method
      assert_equal 1, test_error

      assert_controller_action(test_action)
    end

    it "should correctly report nested routes" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      r = get "/user/12345/product"

      r.body.must_match /12345/

      assert_equal "product./user/:user_id/product", test_action
      assert_equal "http://example.org/user/12345/product", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end

    it "should correctly report nested routes with param" do
      @app = SimpleDemo
      test_action, test_url, test_status, test_method, test_error = nil, nil, nil, nil, nil
      AppOpticsAPM::Span.expects(:createHttpSpan).with do |action, url, _, _duration, status, method, error|
        test_action = action
        test_url = url
        test_status = status
        test_method = method
        test_error = error
      end.once

      r = get "/user/12345/product/show/101010"

      r.body.must_match /12345/
      r.body.must_match /101010/

      assert_equal "product./user/:user_id/product/show/:id", test_action
      assert_equal "http://example.org/user/12345/product/show/101010", test_url
      assert_equal 200, test_status
      assert_equal "GET", test_method
      assert_equal 0, test_error

      assert_controller_action(test_action)
    end
  end
end
