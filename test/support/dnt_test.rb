# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'minitest_helper'
require 'rack/test'
require 'rack/lobster'
require 'appoptics_apm/inst/rack'

class RackTestApp < Minitest::Test
  include Rack::Test::Methods

  def app
    @app = Rack::Builder.new {
      use Rack::CommonLogger
      use Rack::ShowExceptions
      use AppOpticsAPM::Rack
      map "/lobster" do
        use Rack::Lint
        run Rack::Lobster.new
      end
    }
  end

  def setup
    @dnt_original = AppOpticsAPM::Config[:dnt_regexp_compiled]
  end

  def teardown
    AppOpticsAPM::Config[:dnt_regexp_compiled] = @dnt_original
  end

  def test_do_not_trace_static_assets
    clear_all_traces

    get "/assets/static_asset.png"

    traces = get_all_traces
    assert traces.empty?

    assert_equal 404, last_response.status
  end

  def test_do_not_trace_static_assets_with_param
    clear_all_traces

    get "/assets/static_asset.png?body=1"

    traces = get_all_traces
    assert traces.empty?

    assert_equal 404, last_response.status
  end

  def test_do_not_trace_static_assets_with_multiple_params
    clear_all_traces

    get "/assets/static_asset.png?body=1&head=0"

    traces = get_all_traces
    assert traces.empty?

    assert_equal 404, last_response.status
  end

  def test_custom_do_not_trace
    clear_all_traces

    dnt_original = AppOpticsAPM::Config[:dnt_regexp_compiled]
    dnt_regexp = "lobster$"
    AppOpticsAPM::Config[:dnt_regexp_compiled] = Regexp.new(dnt_regexp, AppOpticsAPM::Config[:dnt_opts])

    get "/lobster"

    traces = get_all_traces
    assert traces.empty?

    AppOpticsAPM::Config[:dnt_regexp_compiled] = dnt_original
  end

  def test_complex_do_not_trace
    clear_all_traces

    dnt_original = AppOpticsAPM::Config[:dnt_regexp_compiled]

    # Do not trace .js files _except for_ show.js
    dnt_regexp = "(\.js$)(?<!show.js)"
    AppOpticsAPM::Config[:dnt_regexp_compiled] = Regexp.new(dnt_regexp, AppOpticsAPM::Config[:dnt_opts])

    # First: We shouldn't trace general .js files
    get "/javascripts/application.js"

    traces = get_all_traces
    assert traces.empty?

    # Second: We should trace show.js
    clear_all_traces

    get "/javascripts/show.js"

    traces = get_all_traces
    assert !traces.empty?

    AppOpticsAPM::Config[:dnt_regexp_compiled] = dnt_original
  end

  def test_compile_dnt_regex

  end
end

