# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

unless defined?(JRUBY_VERSION)
  require 'minitest_helper'
  require_relative "../jobs/resque/remote_call_worker_job"
  require_relative "../jobs/resque/error_worker_job"

  Resque.redis = Redis.new(:url => 'redis://:secret_pass@localhost:6379')
  Resque.enqueue(ResqueRemoteCallWorkerJob)  # calling this here once to avoid other calls having an auth span

  class ResqueClientTest < Minitest::Test
    def setup
      clear_all_traces
      @collect_backtraces = AppOpticsAPM::Config[:resqueclient][:collect_backtraces]
      @log_args = AppOpticsAPM::Config[:resqueclient][:log_args]
    end

    def teardown
      AppOpticsAPM::Config[:resqueclient][:collect_backtraces] = @collect_backtraces
      AppOpticsAPM::Config[:resqueclient][:log_args] = @log_args
    end

    def test_appoptics_methods_defined
      [ :enqueue, :enqueue_to, :dequeue ].each do |m|
        assert_equal true, ::Resque.method_defined?("#{m}_with_appoptics")
      end

      assert_equal true, ::Resque::Worker.method_defined?("perform_with_appoptics")
      assert_equal true, ::Resque::Job.method_defined?("fail_with_appoptics")
    end

    def not_tracing_validation
      assert_equal true, Resque.enqueue(ResqueRemoteCallWorkerJob), "not tracing; enqueue return value"
      assert_equal true, Resque.enqueue(ResqueRemoteCallWorkerJob, 1, 2, "3"), "not tracing; enqueue extra params"
    end

    def test_enqueue
      AppOpticsAPM::API.start_trace('resque-client_test', '', {}) do
        Resque.enqueue(ResqueRemoteCallWorkerJob)
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                       traces[4]['Label'], "exit event label"
    end

    def test_dequeue
      AppOpticsAPM::API.start_trace('resque-client_test', '', {}) do
        Resque.dequeue(ResqueRemoteCallWorkerJob, { :generate => :moped })
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                        traces[4]['Label'], "exit event label"
    end

    def test_collect_backtraces_default_value
      assert_equal AppOpticsAPM::Config[:resqueclient][:collect_backtraces], true, "default backtrace collection"
    end

    def test_log_args_default_value
      assert_equal AppOpticsAPM::Config[:resqueclient][:log_args], true, "log_args default "
    end

    def test_obey_collect_backtraces_when_false
      AppOpticsAPM::Config[:resqueclient][:collect_backtraces] = false

      # Queue up a job to be run
      ::AppOpticsAPM::API.start_trace('resque-client_test') do
        Resque.enqueue(ResqueRemoteCallWorkerJob, [1, 2, 3])
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal false,           traces[1].key?('Backtrace')

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                       traces[4]['Label'], "exit event label"
    end

    def test_obey_collect_backtraces_when_true
      AppOpticsAPM::Config[:resqueclient][:collect_backtraces] = true

      # Queue up a job to be run
      ::AppOpticsAPM::API.start_trace('resque-client_test') do
        Resque.enqueue(ResqueRemoteCallWorkerJob, [1, 2, 3])
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal true,           traces[1].key?('Backtrace')

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                       traces[4]['Label'], "exit event label"
    end

    def test_obey_log_args_when_false
      AppOpticsAPM::Config[:resqueclient][:log_args] = false

      # Queue up a job to be run
      ::AppOpticsAPM::API.start_trace('resque-client_test') do
        Resque.enqueue(ResqueRemoteCallWorkerJob, [1, 2, 3])
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal false,           traces[1].key?('Args')

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                       traces[4]['Label'], "exit event label"
    end

    def test_obey_log_args_when_true
      AppOpticsAPM::Config[:resqueclient][:log_args] = true

      # Queue up a job to be run
      ::AppOpticsAPM::API.start_trace('resque-client_test') do
        Resque.enqueue(ResqueRemoteCallWorkerJob, 1, 2, 3)
      end

      traces = get_all_traces

      assert_equal 6, traces.count, "trace count"
      validate_outer_layers(traces, 'resque-client_test')

      assert_equal true,            traces[1].key?('Args')
      assert_equal "[1,2,3]",     traces[1]['Args']

      assert_equal "resque-client",              traces[1]['Layer'], "entry event layer name"
      assert_equal "entry",                      traces[1]['Label'], "entry event label"
      assert_equal "pushq",                      traces[1]['Spec']
      assert_equal "resque",                     traces[1]['Flavor']
      assert_equal "ResqueRemoteCallWorkerJob",  traces[1]['JobName']
      assert_equal "critical",                   traces[1]['Queue']
      assert_equal "resque-client",              traces[4]['Layer'], "exit event layer name"
      assert_equal "exit",                       traces[4]['Label'], "exit event label"
    end
  end
end
