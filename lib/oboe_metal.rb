# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

require 'thread'

# Disable docs and Camelcase warns since we're implementing
# an interface here.  See OboeBase for details.
# rubocop:disable Style/Documentation, Style/MethodName
module AppOpticsAPM
  extend AppOpticsAPMBase
  include Oboe_metal

  class Reporter
    class << self
      ##
      # start
      #
      # Start the AppOpticsAPM Reporter
      #
      def start
        return unless AppOpticsAPM.loaded

        begin
          options = []

          ENV['APPOPTICS_REPORTER'] = 'file' if ENV.key?('APPOPTICS_GEM_TEST')

          case ENV['APPOPTICS_REPORTER']
          when 'file'
            ENV['APPOPTICS_REPORTER_FILE'] = TRACE_FILE
          when 'udp'
            ENV['APPOPTICS_REPORTER_UDP'] = "#{AppOpticsAPM::Config[:reporter_host]}:#{AppOpticsAPM::Config[:reporter_port]}"
          else # default is ssl, service_key is mandatory
            return unless valid_service_key?
            # Oboe will override these settings if there are env settings for them
            options << AppOpticsAPM::Config[:service_key].to_s
            options << AppOpticsAPM::Config[:hostname_alias].to_s
            options << AppOpticsAPM::Config[:debug_level] unless AppOpticsAPM::Config[:debug_level].nil?
          end
          AppOpticsAPM.reporter = Oboe_metal::Reporter.new(*options)

          # Only report __Init from here if we are not instrumenting a framework.
          # Otherwise, frameworks will handle reporting __Init after full initialization
          unless defined?(::Rails) || defined?(::Sinatra) || defined?(::Padrino) || defined?(::Grape)
            AppOpticsAPM::API.report_init
          end

        rescue => e
          $stderr.puts e.message
          raise
        end
      end
      alias :restart :start

      def valid_service_key?
        service_key = (ENV['APPOPTICS_SERVICE_KEY'] || AppOpticsAPM::Config[:service_key]).to_s
        if service_key == ''
          AppOpticsAPM.logger.warn '[appoptics_apm/warn] APPOPTICS_SERVICE_KEY not set. Cannot submit data.'
          AppOpticsAPM.loaded = false
          return false
        elsif service_key !~ /^[0-9a-fA-F]{64}:[-.:_?\\\/\w ]{1,255}$/
          AppOpticsAPM.logger.warn '[appoptics_apm/warn] APPOPTICS_SERVICE_KEY problem. No service name or api token in wrong format. Cannot submit data.'
          AppOpticsAPM.loaded = false
          return false
        end
        true
      end
      ##
      # sendReport
      #
      # Send the report for the given event
      #
      def sendReport(evt)
        AppOpticsAPM.reporter.sendReport(evt)
      end

      ##
      # sendStatus
      #
      # Send the report for the given event
      #
      def sendStatus(evt, context = nil)
        AppOpticsAPM.reporter.sendStatus(evt, context)
      end

      ##
      # clear_all_traces
      #
      # Truncates the trace output file to zero
      #
      def clear_all_traces
        File.truncate(TRACE_FILE, 0)
      end

      ##
      # get_all_traces
      #
      # Retrieves all traces written to the trace file
      #
      def get_all_traces
        io = File.open(TRACE_FILE, 'r')
        contents = io.readlines(nil)

        return contents if contents.empty?

        traces = []

        #
        # We use Gem.loaded_spec because older versions of the bson
        # gem didn't even have a version embedded in the gem.  If the
        # gem isn't in the bundle, it should rightfully error out
        # anyways.
        #
        if Gem.loaded_specs['bson'].version.to_s < '4.0'
          s = StringIO.new(contents[0])

          until s.eof?
            traces << if ::BSON.respond_to? :read_bson_document
                        BSON.read_bson_document(s)
                      else
                        BSON::Document.from_bson(s)
                      end
          end
        else
          bbb = BSON::ByteBuffer.new(contents[0])
          until bbb.length == 0
            traces << Hash.from_bson(bbb)
          end
        end

        traces
      end
    end
  end

  module EventUtil
    def self.metadataString(evt)
      evt.metadataString
    end
  end

  class << self
    def sample?(opts = {})
      # Return false if no-op mode
      return false unless AppOpticsAPM.loaded

      # Assure defaults since SWIG enforces Strings
      xtrace  = opts[:xtrace]     ? opts[:xtrace].to_s.strip       : APPOPTICS_STR_BLANK

      # the first arg has changed to be the service name, blank means to use the default (from the service key)
      rv = AppOpticsAPM::Context.sampleRequest(APPOPTICS_STR_BLANK, xtrace)

      if rv == 0
        AppOpticsAPM.sample_rate = -1
        AppOpticsAPM.sample_source = -1
        false
      else
        # liboboe version > 1.3.1 returning a bit masked integer with SampleRate and
        # source embedded
        AppOpticsAPM.sample_rate = (rv & SAMPLE_RATE_MASK)
        AppOpticsAPM.sample_source = (rv & SAMPLE_SOURCE_MASK) >> 24
        true
      end
    rescue StandardError => e
      AppOpticsAPM.logger.debug "[oboe/error] sample? error: #{e.inspect}"
      false
    end

    def set_tracing_mode(mode)
      return unless AppOpticsAPM.loaded

      value = mode.to_sym

      case value
      when :never
        AppOpticsAPM::Context.setTracingMode(APPOPTICS_TRACE_NEVER)

      when :always
        AppOpticsAPM::Context.setTracingMode(APPOPTICS_TRACE_ALWAYS)

      else
        AppOpticsAPM.logger.fatal "[oboe/error] Invalid tracing mode set: #{mode}"
        AppOpticsAPM::Context.setTracingMode(APPOPTICS_TRACE_NEVER)
      end
    end

    def set_sample_rate(rate)
      return unless AppOpticsAPM.loaded

      # Update liboboe with the new SampleRate value
      AppOpticsAPM::Context.setDefaultSampleRate(rate.to_i)
    end
  end
end
# rubocop:enable Style/Documentation

AppOpticsAPM.loaded = true
AppOpticsAPM.config_lock = Mutex.new
