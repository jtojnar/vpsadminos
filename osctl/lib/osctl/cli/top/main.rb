require 'osctl/cli/command'

module OsCtl::Cli
  class Top::Main < Command
    def start
      model = Top::Model.new(enable_iostat: opts[:iostat])
      model.setup

      if gopts[:json]
        klass = Top::JsonExporter

      else
        klass = Top::Tui
      end

      view = klass.new(model, opts[:rate])
      view.start
    end
  end
end
