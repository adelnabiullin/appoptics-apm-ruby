if defined?(ActionController::Base) and Rails::VERSION::MAJOR == 2
  ActionController::Base.class_eval do
    alias :old_perform_action :perform_action
    alias :old_rescue_action :rescue_action
    alias :old_process :process

    def process(request, response)
      header = request.headers['X-Trace']
      result, header = Oboe::Inst.trace_start_layer_block('rails', header) do
        old_process(request, response)
      end

      response.headers['X-Trace'] = header if header
      result
    end

    def perform_action(*arguments)
      Oboe::Inst.log('rails', 'info', @_request.path_parameters)
      old_perform_action(*arguments)
    end

    def rescue_action(exn)
      Oboe::Inst.log_exception('rails', exn)
      old_rescue_action(exn)
    end
  end
end

=begin
if defined?(ActionController::Base) and Rails::VERSION::MAJOR == 3
  ActionController::Base.class_eval do
    alias :old_process_action :perform_action
    alias :old_process :process
    alias :old_render :render
    alias :old_rescue_action :rescue_action

    def process(*args)
      header = request.headers['X-Trace']
      result, header = Oboe::Inst.trace_start_layer_block('rails', header) do
        old_process(request, response)
      end

      response.headers['X-Trace'] = header if header
      result
    end

    def process_action(*args)
      opts = {
        :Controller => self.controller.name,
        :Action => self.action_name,
      }

      Oboe::Inst.log('rails', 'info', opts)
      old_process_action(*args)
    end

    def render; end
    def rescue_action; end
  end
end
=end
