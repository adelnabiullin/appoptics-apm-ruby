# Copyright (c) 2013 AppNeta, Inc.
# All rights reserved.

module TraceView
  module API
    ##
    # Module that provides profiling of arbitrary blocks of code
    module Profiling
      ##
      # Public: Profile a given block of code. Detect any exceptions thrown by
      # the block and report errors.
      #
      # profile_name - A name used to identify the block being profiled.
      # report_kvs - A hash containing key/value pairs that will be reported along
      #              with the event of this profile (optional).
      # with_backtrace - Boolean to indicate whether a backtrace should
      #                  be collected with this trace event.
      #
      # Example
      #
      #   def computation(n)
      #     TraceView::API.profile('fib', { :n => n }) do
      #       fib(n)
      #     end
      #   end
      #
      # Returns the result of the block.
      def profile(profile_name, report_kvs = {}, with_backtrace = false)
        report_kvs[:Language] ||= :ruby
        report_kvs[:ProfileName] ||= profile_name
        report_kvs[:Backtrace] = TraceView::API.backtrace if with_backtrace

        TraceView::API.log(nil, 'profile_entry', report_kvs)

        begin
          yield
        rescue => e
          log_exception(nil, e)
          raise
        ensure
          exit_kvs = {}
          exit_kvs[:Language] = :ruby
          exit_kvs[:ProfileName] = report_kvs[:ProfileName]

          TraceView::API.log(nil, 'profile_exit', exit_kvs)
        end
      end

      ##
      # Public: Profile an arbitrary method on a class or module.  That method can be of any (accessible)
      # type (instance, singleton etc.).
      #
      def profile_method(klass, method, report_arguments = false, report_result = false)

        # Argument validation
        unless klass.is_a?(Class) || klass.is_a?(Module)
          TraceView.logger.warn "[traceview/error] Not sure what to do with #{klass}.  Send a class or module."
          return false
        end

        unless method.is_a?(Symbol)
          if method.is_a?(String)
            method = method.to_sym
          else
            TraceView.logger.warn "[traceview/error] Not sure what to do with #{method}.  Send a string or symbol for method."
            return false
          end
        end

        instance_method = klass.instance_methods.include?(method) || klass.private_instance_methods.include?(method)
        class_method = klass.singleton_methods.include?(method)

        # Make sure the request klass::method exists
        if !instance_method && !class_method
          TraceView.logger.warn "[traceview/error] Can't instrument #{klass}.#{method} as it doesn't seem to exist."
          TraceView.logger.warn "[traceview/error] #{__FILE__}:#{__LINE__}"
          return false
        end

        # assert instance_method || class_method

        # Strip '!' or '?' from method if present
        safe_method_name = method.to_s.chop if method.to_s =~ /\?$|\!$/
        safe_method_name ||= method

        without_traceview = "#{safe_method_name}_without_traceview"
        with_traceview    = "#{safe_method_name}_with_traceview"

        unless klass.instance_methods.include?(with_traceview.to_sym) ||
          klass.singleton_methods.include?(with_traceview.to_sym)

          ::TraceView::Util.send_include(klass, ::TraceView::MethodProfiling)

          report_kvs = {}
          report_kvs[:Language] ||= :ruby
          report_kvs[:ProfileName] ||= method
          report_kvs[:Backtrace] = TraceView::API.backtrace if TraceView::Config[:method_profiling][:collect_backtraces]

          if klass.is_a?(Class)
            report_kvs[:Class] = klass.to_s
          else
            report_kvs[:Module] = klass.to_s
          end

          source_location = []
          if instance_method
            ::TraceView::Util.send_include(klass, ::TraceView::MethodProfiling)
            source_location = klass.instance_method(method).source_location
          elsif class_method
            ::TraceView::Util.send_extend(klass, ::TraceView::MethodProfiling)
            source_location = klass.method(method).source_location
          end
          report_kvs[:File] = source_location[0]
          report_kvs[:LineNumber] = source_location[1]

          if instance_method
            klass.class_eval do
              define_method(with_traceview) { | *args, &block |
                profile_wrapper(without_traceview, report_kvs, report_arguments, report_result, *args, &block)
              }

              alias_method without_traceview, "#{method}"
              alias_method "#{method}", with_traceview
            end
          elsif class_method
            klass.define_singleton_method(with_traceview) { | *args, &block |
              profile_wrapper(without_traceview, report_kvs, report_arguments, report_result, *args, &block)
            }

            klass.singleton_class.class_eval do
              alias_method without_traceview, "#{method}"
              alias_method "#{method}", with_traceview
            end
          end

        else
          TraceView.logger.warn "[traceview/error] #{klass}::#{method} already profiled."
          TraceView.logger.warn "[traceview/error] #{__FILE__}:#{__LINE__}"
          return false
        end
        true
      end
    end
  end
end
