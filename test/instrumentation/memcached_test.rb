# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'minitest_helper'

unless defined?(JRUBY_VERSION)
  describe "Memcached" do
    require 'memcached'
    require 'memcached/rails'

    before do
      clear_all_traces
      @mc = ::Memcached::Rails.new(:servers => ['127.0.0.1'])

      # These are standard entry/exit KVs that are passed up with all mongo operations
      @entry_kvs = {
        'Layer' => 'memcache',
        'Label' => 'entry' }

      @info_kvs = {
        'Layer' => 'memcache',
        'Label' => 'info' }

      @exit_kvs = { 'Layer' => 'memcache', 'Label' => 'exit' }
      @collect_backtraces = AppOpticsAPM::Config[:memcached][:collect_backtraces]
    end

    after do
      AppOpticsAPM::Config[:memcached][:collect_backtraces] = @collect_backtraces
    end

    it 'Stock Memcached should be loaded, defined and ready' do
      defined?(::Memcached).wont_match nil
      defined?(::Memcached::Rails).wont_match nil
    end

    it 'Memcached should have appoptics_apm methods defined' do
      AppOpticsAPM::API::Memcache::MEMCACHE_OPS.each do |m|
        if ::Memcached.method_defined?(m)
          ::Memcached.method_defined?("#{m}_with_appoptics").must_equal true
        end
        ::Memcached::Rails.method_defined?(:get_multi_with_appoptics).must_equal true
      end
    end

    it "should trace set" do
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.set('testKey', 'blah')
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "set"
      traces[1]['KVKey'].must_equal "testKey"
    end

    it "should trace get" do
      @mc.set('testKey', 'blah')

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.get('testKey')
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "get"
      traces[1]['KVKey'].must_equal "testKey"
    end

    it "should trace get_multi" do
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.get_multi(['one', 'two', 'three', 'four', 'five', 'six'])
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "get_multi"

      traces[2]['KVKeyCount'].must_equal 6
      traces[2].has_key?('KVHitCount').must_equal true
    end

    it "should trace add" do
      @mc.delete('testAdd')
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.add('testAdd', 'x', 1200)
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "add"
      traces[1]['KVKey'].must_equal "testAdd"
    end

    it "should trace append" do
      @mc.set('rawKey', "Peanut Butter ", 600, :raw => true)
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.append('rawKey', "Jelly")
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "append"
      traces[1]['KVKey'].must_equal "rawKey"
    end

    it "should trace decr" do
      @mc.set('some_key_counter', "100", 0, false)

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.decr('some_key_counter', 1)
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "decr"
      traces[1]['KVKey'].must_equal "some_key_counter"
    end

    it "should trace increment" do
      @mc.set('some_key_counter', "100", 0, false)

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.incr("some_key_counter", 1)
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "incr"
      traces[1]['KVKey'].must_equal "some_key_counter"
    end

    it "should trace replace" do
      @mc.set('some_key', 'blah')
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.replace("some_key", "woop")
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "replace"
      traces[1]['KVKey'].must_equal "some_key"
    end

    it "should trace delete" do
      @mc.set('some_key', 'blah')
      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.delete("some_key")
      end

      traces = get_all_traces
      traces.count.must_equal 4

      validate_outer_layers(traces, 'memcached_test')
      validate_event_keys(traces[1], @entry_kvs)
      validate_event_keys(traces[2], @exit_kvs)

      traces[1]['KVOp'].must_equal "delete"
      traces[1]['KVKey'].must_equal "some_key"
    end

    it "should properly log errors" do
      @mc.set('testKey', 'x', 1200)

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.add('testKey', 'x', 1200)
      end

      traces = get_all_traces

      error_trace = traces.find { |trace| trace['Label'] == 'error' }

      error_trace['Spec'].must_equal 'error'
      error_trace['Label'].must_equal 'error'
      error_trace['ErrorClass'].must_equal "Memcached::NotStored"
      error_trace['ErrorMsg'].must_equal "Memcached::NotStored"
      assert_equal 1, traces.select { |trace| trace['Label'] == 'error' }.count
    end

    it "should obey :collect_backtraces setting when true" do
      AppOpticsAPM::Config[:memcached][:collect_backtraces] = true

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.set('some_key', 1)
      end

      traces = get_all_traces
      traces.find { |tr| tr['Layer'] == 'memcache' && tr['Label'] == 'exit'}.has_key?('Backtrace')
    end

    it "should obey :collect_backtraces setting when false" do
      AppOpticsAPM::Config[:memcached][:collect_backtraces] = false

      AppOpticsAPM::API.start_trace('memcached_test', '', {}) do
        @mc.set('some_key', 1)
      end

      traces = get_all_traces
      layer_doesnt_have_key(traces, 'memcache', 'Backtrace')
    end
  end
end
