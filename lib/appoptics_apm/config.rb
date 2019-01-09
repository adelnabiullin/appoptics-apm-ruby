# Copyright (c) 2016 SolarWinds, LLC.
# All rights reserved.

module AppOpticsAPM
  ##
  # This module exposes a nested configuration hash that can be used to
  # configure and/or modify the functionality of the appoptics_apm gem.
  #
  # Use AppOpticsAPM::Config.show to view the entire nested hash.
  #
  module Config
    @@config = {}

    @@instrumentation = [:action_controller, :action_controller_api, :action_view,
                         :active_record, :bunnyclient, :bunnyconsumer, :cassandra, :curb,
                         :dalli, :delayed_jobclient, :delayed_jobworker,
                         :em_http_request, :excon, :faraday, :grpc_client, :grpc_server, :grape,
                         :httpclient, :nethttp, :memcached, :mongo, :moped, :padrino, :rack, :redis,
                         :resqueclient, :resqueworker, :rest_client,
                         :sequel, :sidekiqclient, :sidekiqworker, :sinatra, :typhoeus]

    # Subgrouping of instrumentation
    @@http_clients = [:curb, :excon, :em_http_request, :faraday, :httpclient, :nethttp, :rest_client, :typhoeus]

    ##
    # load_config_file
    #
    # There are 3 possible locations for the config file:
    # Rails default, ENV['APPOPTICS_APM_CONFIG_RUBY'], or the gem's default
    #
    # Hierarchie:
    # 1 - Rails default: config/initializers/appoptics_apm.rb
    #     (also loaded  by Rails, but we can't reliably determine if Rails is running)
    # 2 - ENV['APPOPTICS_APM_CONFIG_RUBY']
    # 3 - Gem default: <startup_dir>/appoptics_apm_config.rb
    #
    def self.load_config_file
      config_files = []

      # Check for the rails config file
      config_file = File.join(Dir.pwd, 'config/initializers/appoptics_apm.rb')
      config_files << config_file if File.exist?(config_file)

      # Check for file set by env variable
      if ENV.key?('APPOPTICS_APM_CONFIG_RUBY')
        if File.exist?(ENV['APPOPTICS_APM_CONFIG_RUBY']) && !File.directory?(ENV['APPOPTICS_APM_CONFIG_RUBY'])
          config_files << ENV['APPOPTICS_APM_CONFIG_RUBY']
        elsif File.exist?(File.join(ENV['APPOPTICS_APM_CONFIG_RUBY'], 'appoptics_apm_config.rb'))
          config_files << File.join(ENV['APPOPTICS_APM_CONFIG_RUBY'], 'appoptics_apm_config.rb')
        else
          $stderr.puts 'Could not find the configuration file set by the APPOPTICS_APM_CONFIG_RUBY environment variable:'
          $stderr.puts "#{ENV['APPOPTICS_APM_CONFIG_RUBY']}"
        end
      end

      # Check for default config file
      config_file = File.join(Dir.pwd, 'appoptics_apm_config.rb')
      config_files << config_file if File.exist?(config_file)

      return if config_files.empty?  # we use the defaults from the template in this case

      if config_files.size > 1
        $stderr.puts 'Found multiple configuration files, using the first one listed:'
        config_files.each { |path| $stderr.puts "  #{path}" }
      end
      load(config_files[0])
      check_env_vars
      precompile_dnt
    end

    # There are 4 variables that can be set in the config file or as env vars.
    # Oboe will override vars passed in if it finds an environment variable
    # :debug_level and :verbose need special consideration, because they are used in Ruby
    def self.check_env_vars
      AppOpticsAPM::Config[:debug_level] = 3 unless (-1..6).cover?(AppOpticsAPM::Config[:debug_level])

      # let's find and use the  equivalent debug level for ruby
      debug_level = ENV['APPOPTICS_DEBUG_LEVEL'] ? ENV['APPOPTICS_DEBUG_LEVEL'].to_i : AppOpticsAPM::Config[:debug_level]
      # there should be no logging if APPOPTICS_DEBUG_LEVEL == -1
      # In Ruby level 5 is UNKNOWN and it can log, but level 6 is quiet
      AppOpticsAPM.logger.level = debug_level.negative? ? 6 : [4 - debug_level, 0].max

      # the verbose setting is only relevant for ruby and not the c-lib
      return unless ENV.key?('APPOPTICS_GEM_VERBOSE')
      AppOpticsAPM::Config[:verbose] = ENV['APPOPTICS_GEM_VERBOSE'].downcase == 'true'
    end

    # make sure we have a precompiled regex for "do-not-trace" filters
    # also sometimes called "static assets"
    def self.precompile_dnt
      return if AppOpticsAPM::Config[:dnt_regexp_compiled]

      assets_source ||= Regexp.union(AppOpticsAPM::Config[:dnt_assets]).source
      AppOpticsAPM::Config[:dnt_regexp] ||= "#{assets_source}(\\?.+){0,1}$"
      AppOpticsAPM::Config[:dnt_regexp_compiled] = Regexp.new(AppOpticsAPM::Config[:dnt_regexp], AppOpticsAPM::Config[:dnt_opts])
    end

    ##
    # print_config
    #
    # print configurations one per line
    # to create an output similar to the content of the config file
    #
    def self.print_config
      AppOpticsAPM.logger.warn "# General configurations"
      non_instrumentation = @@config.keys - @@instrumentation
      non_instrumentation.each do |config|
        AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:#{config}] = #{@@config[config]}"
      end

      AppOpticsAPM.logger.warn "\n# Instrumentation specific configurations"
      AppOpticsAPM.logger.warn "# Enabled/Disabled Instrumentation"
      @@instrumentation.each do |config|
        AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:#{config}][:enabled] = #{@@config[config][:enabled]}"
      end

      AppOpticsAPM.logger.warn "\n# Enabled/Disabled Backtrace Collection"
      @@instrumentation.each do |config|
        AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:#{config}][:collect_backtraces] = #{@@config[config][:collect_backtraces]}"
      end

      AppOpticsAPM.logger.warn "\n# Logging of outgoing HTTP query args"
      @@instrumentation.each do |config|
        AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:#{config}][:log_args] = #{@@config[config][:log_args] || false}"
      end

      AppOpticsAPM.logger.warn "\n# Bunny Controller and Action"
      AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:bunnyconsumer][:controller] = #{@@config[:bunnyconsumer][:controller].inspect}"
      AppOpticsAPM.logger.warn "AppOpticsAPM::Config[:bunnyconsumer][:action] = #{@@config[:bunnyconsumer][:action].inspect}"
      nil
    end

    ##
    # initialize
    #
    # Initializer method to set everything up with a default configuration.
    # The defaults are read from the template configuration file.
    #
    def self.initialize(_data = {})
      @@instrumentation.each { |k| @@config[k] = {} }
      @@config[:transaction_name] = {}

      # Always load the template, it has all the keys and defaults defined,
      # no guarantee of completeness in the user's config file
      load(File.join(File.dirname(File.dirname(__FILE__)),
                    'rails/generators/appoptics_apm/templates/appoptics_apm_initializer.rb'))

      # to make sure we include env vars
      check_env_vars
    end

    def self.update!(data)
      data.each do |key, value|
        self[key] = value
      end
    end

    def self.merge!(data)
      update!(data)
    end

    def self.[](key)
      if key == :resque
        AppOpticsAPM.logger.warn '[appoptics_apm/warn] :resque config is deprecated.  It is now split into :resqueclient and :resqueworker.'
        AppOpticsAPM.logger.warn "[appoptics_apm/warn] Called from #{Kernel.caller[0]}"
      end

      @@config[key.to_sym]
    end

    ##
    # []=
    #
    # Config variable assignment method.  Here we validate and store the
    # assigned value(s) and trigger any secondary action needed.
    #
    # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    def self.[]=(key, value)
      @@config[key.to_sym] = value

      case key
      when :sampling_rate
        AppOpticsAPM.logger.warn '[appoptics_apm/config] sampling_rate is not a supported setting for AppOpticsAPM::Config.  ' \
                         'Please use :sample_rate.'

      when :sample_rate
        unless value.is_a?(Integer) || value.is_a?(Float)
          AppOpticsAPM.logger.warn "[appoptics_apm/config] :sample_rate must be a number between 0 and 1000000 (1m) " \
                                   "(provided: #{value}), corrected to 0"
          value = 0
        end

        # Validate :sample_rate value
        unless value.between?(0, 1e6)
          value_1 = value
          value = value_1 < 0 ? 0 : 1_000_000
          AppOpticsAPM.logger.warn "[appoptics_apm/config] :sample_rate must be between 0 and 1000000 (1m) " \
                                   "(provided: #{value_1}), corrected to #{value}"
        end

        # Assure value is an integer
        @@config[key.to_sym] = value.to_i
        AppOpticsAPM.set_sample_rate(value) if AppOpticsAPM.loaded

      when :action_blacklist
        AppOpticsAPM.logger.warn "[appoptics_apm/config] :action_blacklist has been deprecated and no longer functions."

      when :resque
        AppOpticsAPM.logger.warn "[appoptics_apm/config] :resque config is deprecated.  It is now split into :resqueclient and :resqueworker."
        AppOpticsAPM.logger.warn "[appoptics_apm/config] Called from #{Kernel.caller[0]}"

      when :include_url_query_params # DEPRECATED
        # Obey the global flag and update all of the per instrumentation
        # <tt>:log_args</tt> values.
        @@config[:rack][:log_args] = value

      when :include_remote_url_params # DEPRECATED
        # Obey the global flag and update all of the per instrumentation
        # <tt>:log_args</tt> values.
        @@http_clients.each do |i|
          @@config[i][:log_args] = value
        end

      # Update liboboe if updating :tracing_mode
      when :tracing_mode
        AppOpticsAPM.set_tracing_mode(value.to_sym) if AppOpticsAPM.loaded

        # Make sure that the mode is stored as a symbol
        @@config[key.to_sym] = value.to_sym
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

    def self.method_missing(sym, *args)
      class_var_name = "@@#{sym}"

      if sym.to_s =~ /(.+)=$/
        self[$1] = args.first

      # Try part of the @@config hash first
      elsif @@config.key?(sym)
        self[sym]

      # Then try as a class variable
      elsif class_variable_defined?(class_var_name.to_sym)
        class_eval(class_var_name)

      # fall back to super
      else
        super
      end
    end

    def self.respond_to_missing?(sym, include_private = false)
      class_var_name = "@@#{sym}"

      return true if sym.to_s =~ /(.+)=$/

      # Try part of the @@config hash first
      return true if @@config.key?(sym)

      # Then try as a class variable
      return true if class_variable_defined?(class_var_name.to_sym)

      super
    end
  end
end

AppOpticsAPM::Config.initialize
