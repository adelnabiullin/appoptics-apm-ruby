# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.
require 'minitest_helper'

describe "AppOpticsAPMMethodProfiling" do
  before do
    clear_all_traces
    # Conditionally Undefine TestWorker
    # http://stackoverflow.com/questions/11503558/how-to-undefine-class-in-ruby
    Object.send(:remove_const, :TestKlass) if defined?(TestKlass)
    Object.send(:remove_const, :TestModule) if defined?(TestModule)
  end

  it 'should be loaded, defined and ready' do
    defined?(::AppOpticsAPM::MethodProfiling).wont_match nil
    assert_equal true, AppOpticsAPM::API.respond_to?(:profile_method), "has profile_method method"
  end

  it 'should return false for bad arguments' do
    class TestKlass
      def do_work
        return 687
      end
    end

    # Bad first param
    rv = AppOpticsAPM::API.profile_method('blah', :do_work)
    assert_equal false, rv, "Return value must be false for bad args"

    # Bad first param
    rv = AppOpticsAPM::API.profile_method(TestKlass, 52)
    assert_equal false, rv, "Return value must be false for bad args"
  end

  it 'should profile class instance methods' do
    class TestKlass
      def do_work
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should not double profile already profiled methods' do
    class TestKlass
      def do_work
        return 687
      end
    end

    # Attempt to double profile
    rv = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, rv, "Return value must be true"

    rv = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal false, rv, "Return value must be false"

    with_tv = TestKlass.instance_methods.select{ |m| m == :do_work_with_appoptics }
    assert_equal with_tv.count, 1, ":do_work_with_appoptics method count"

    without_tv = TestKlass.instance_methods.select{ |m| m == :do_work_without_appoptics }
    assert_equal without_tv.count, 1, ":do_work_without_appoptics method count"
  end

  it 'should error out for non-existent methods' do
    class TestKlass
      def do_work
        return 687
      end
    end

    rv = AppOpticsAPM::API.profile_method(TestKlass, :does_not_exist)
    assert_equal false, rv, "Return value must be false"

    with_tv = TestKlass.instance_methods.select{ |m| m == :does_not_exit_with_appoptics }
    assert_equal with_tv.count, 0, ":does_not_exit_with_appoptics method count"

    without_tv = TestKlass.instance_methods.select{ |m| m == :does_not_exit_without_appoptics }
    assert_equal without_tv.count, 0, ":does_not_exit_without_appoptics method count"
  end

  it 'should trace class singleton methods' do
    class TestKlass
      def self.do_work
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      result = TestKlass.do_work
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should trace class private instance methods' do
    class TestKlass
      private
      def do_work_privately
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work_privately)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work_privately
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work_privately"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work_privately"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work_privately"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should trace class private singleton methods' do
    class TestKlass
      private
      def self.do_work_privately
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work_privately)
    assert_equal true, result, "profile_method return value must be true"

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      result = TestKlass.do_work_privately
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work_privately"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work_privately"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work_privately"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should trace module singleton methods' do
    module TestModule
      def self.do_work
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestModule, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      result = TestModule.do_work
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Module"] = "TestModule"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Class").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should trace module instance methods' do
    module TestModule
      def do_work
        return 687
      end
    end

    # Profile the module before including in a class
    result = AppOpticsAPM::API.profile_method(TestModule, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    class TestKlass
      include TestModule
    end

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      result = TestKlass.new.do_work
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Module"] = "TestModule"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Class").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should profile methods that use blocks' do
    class TestKlass
      def self.do_work(*)
        yield
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      result = TestKlass.do_work do
        787
      end
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 787

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false
  end

  it 'should not store arguments and return value by default' do
    class TestKlass
      def do_work(*)
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work(:ok => :blue)
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false

    traces[2].key?("Arguments").must_equal false
    traces[2].key?("ReturnValue").must_equal false
  end

  it 'should store arguments and return value when asked' do
    class TestKlass
      def do_work(*)
        return 687
      end
    end

    opts = {}
    opts[:arguments] = true
    opts[:result] = true

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work, opts)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work(:ok => :blue)
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Layer").must_equal false
    traces[1].key?("Module").must_equal false
    traces[1].key?("File").must_equal true
    traces[1].key?("LineNumber").must_equal true

    kvs.clear
    kvs["Label"] = "profile_exit"
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"

    validate_event_keys(traces[2], kvs)
    traces[2].key?("Layer").must_equal false

    traces[2].key?("Arguments").must_equal true
    traces[2]["Arguments"].must_equal "[{:ok=>:blue}]"

    traces[2].key?("ReturnValue").must_equal true
    traces[2]["ReturnValue"].must_equal 687
  end

  it 'should not report backtraces by default' do
    class TestKlass
      def do_work(*)
        return 687
      end
    end

    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work(:ok => :blue)
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces.each { |t|
      t.key?("Backtrace").must_equal false, "shoudn't have backtrace"
    }
  end

  it 'should report backtraces when requested' do
    class TestKlass
      def do_work(*)
        return 687
      end
    end

    opts = { :backtrace => true }
    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work, opts)
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work(:ok => :blue)
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Backtrace").must_equal true, "should report a backtrace"
  end

  it 'should report extra KVs when requested' do
    class TestKlass
      def do_work(*)
        return 687
      end
    end

    opts = { :backtrace => true }
    result = AppOpticsAPM::API.profile_method(TestKlass, :do_work, opts, :another => "value")
    assert_equal true, result, "profile_method return value must be true"

    result = nil

    ::AppOpticsAPM::API.start_trace('method_profiling', '', {}) do
      # Call the profiled class method
      result = TestKlass.new.do_work(:ok => :blue)
    end

    traces = get_all_traces
    traces.count.must_equal 4
    assert valid_edges?(traces), "Trace edge validation"

    validate_outer_layers(traces, 'method_profiling')

    result.must_equal 687

    kvs = {}
    kvs["Label"] = 'profile_entry'
    kvs["Language"] = "ruby"
    kvs["ProfileName"] = "do_work"
    kvs["Class"] = "TestKlass"
    kvs["MethodName"] = "do_work"
    kvs["another"] = "value"

    validate_event_keys(traces[1], kvs)

    traces[1].key?("Backtrace").must_equal true, "should report a backtrace"
  end
end
