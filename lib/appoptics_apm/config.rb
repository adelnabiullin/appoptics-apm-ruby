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
                         :em_http_request, :excon, :faraday, :grape,
                         :httpclient, :nethttp, :memcached, :mongo, :moped, :rack, :redis,
                         :resqueclient, :resqueworker, :rest_client,
                         :sequel, :sidekiqclient, :sidekiqworker, :typhoeus]

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

      return if config_files.empty?

      if config_files.size > 1
        $stderr.puts 'Found multiple configuration files, using the first one listed:'
        config_files.each { |path| $stderr.puts "  #{path}" }
      end
      load(config_files[0])
    end

    ##
    # print_config
    #
    # print configurations one per line
    # to create an output similar to the content of the config file
    #
    def self.print_config
      puts "# General configurations"
      non_instrumentation = @@config.keys - @@instrumentation
      non_instrumentation.each do |config|
        puts "AppOpticsAPM::Config[:#{config}] = #{@@config[config]}"
      end

      puts "\n# Instrumentation specific configurations"
      puts "# Enabled/Disabled Instrumentation"
      @@instrumentation.each do |config|
        puts "AppOpticsAPM::Config[:#{config}][:enabled] = #{@@config[config][:enabled]}"
      end

      puts "\n# Enabled/Disabled Backtrace Collection"
      @@instrumentation.each do |config|
        puts "AppOpticsAPM::Config[:#{config}][:collect_backtraces] = #{@@config[config][:collect_backtraces]}"
      end

      puts "\n# Logging of outgoing HTTP query args"
      @@instrumentation.each do |config|
        puts "AppOpticsAPM::Config[:#{config}][:log_args] = #{@@config[config][:log_args]}"
      end

      puts "\n# Bunny Controller and Action"
      puts "AppOpticsAPM::Config[:bunnyconsumer][:controller] = #{@@config[:bunnyconsumer][:controller].inspect}"
      puts "AppOpticsAPM::Config[:bunnyconsumer][:action] = #{@@config[:bunnyconsumer][:action].inspect}"
      nil
    end

    ##
    # initialize
    #
    # Initializer method to set everything up with a default configuration.
    # The defaults are read from the template configuration file.
    #
    # rubocop:disable Metrics/AbcSize
    def self.initialize(_data = {})
      @@instrumentation.each do |k|
        @@config[k] = {}
      end
      @@config[:transaction_name] = {}
      load(File.join(File.dirname(File.dirname(__FILE__)),
                    'rails/generators/appoptics_apm/templates/appoptics_apm_initializer.rb'))
    end
    # rubocop:enable Metrics/AbcSize

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

      if key == :sampling_rate
        AppOpticsAPM.logger.warn '[appoptics_apm/config] sampling_rate is not a supported setting for AppOpticsAPM::Config.  ' \
                         'Please use :sample_rate.'

      elsif key == :sample_rate
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

      elsif key == :action_blacklist
        AppOpticsAPM.logger.warn "[appoptics_apm/config] :action_blacklist has been deprecated and no longer functions."

      elsif key == :resque
        AppOpticsAPM.logger.warn "[appoptics_apm/config] :resque config is deprecated.  It is now split into :resqueclient and :resqueworker."
        AppOpticsAPM.logger.warn "[appoptics_apm/config] Called from #{Kernel.caller[0]}"

      elsif key == :include_url_query_params # DEPRECATED
        # Obey the global flag and update all of the per instrumentation
        # <tt>:log_args</tt> values.
        @@config[:rack][:log_args] = value

      elsif key == :include_remote_url_params # DEPRECATED
        # Obey the global flag and update all of the per instrumentation
        # <tt>:log_args</tt> values.
        @@http_clients.each do |i|
          @@config[i][:log_args] = value
        end

      # Update liboboe if updating :tracing_mode
      elsif key == :tracing_mode
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
      else
        # Try part of the @@config hash first
        if @@config.key?(sym)
          self[sym]

        # Then try as a class variable
        elsif self.class_variable_defined?(class_var_name.to_sym)
          self.class_eval(class_var_name)

        # Congrats - You've won a brand new nil...
        else
          nil
        end
      end
    end
  end
end

AppOpticsAPM::Config.initialize
