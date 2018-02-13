module OsCtld
  class Commands::Container::Restart < Commands::Logged
    handle :ct_restart

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      ct.exclusively do
        next error('restart not available') unless ct.can_start?
        call_cmd(Commands::Container::Stop, id: ct.id)
        call_cmd(Commands::Container::Start, id: ct.id, force: true)
      end
    end
  end
end
