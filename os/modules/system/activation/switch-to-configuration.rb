#!@ruby@/bin/ruby
require 'json'

class Configuration
  OUT = '@out@'
  ETC = '@etc@'
  CURRENT_SYSTEM = '/run/current-system'
  CURRENT_BIN = File.join(CURRENT_SYSTEM, 'sw/bin')
  NEW_BIN = File.join(OUT, 'sw', 'bin')
  INSTALL_BOOTLOADER = '@installBootLoader@'

  class << self
    %i(boot switch test).each do |m|
      define_method(m) { new(dry_run: false).send(m) }
    end
  end

  def self.dry_run
    new(dry_run: true).dry_run
  end

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}
  end

  def dry_run
    puts 'probing runit services...'
    services = Services.new(**opts)

    puts 'probing pools...'
    pools = Pools.new(**opts)
    pools.export
    pools.rollback

    if pools.error.any?
      puts "unable to handle pools: #{pools.error.map(&:name).join(',')}"
    end

    puts 'would stop deprecated services...'
    services.stop.each(&:stop)

    puts 'would stop changed services...'
    services.restart.each(&:stop)

    puts 'would activate the configuration...'
    activate

    services.switch_runlevel

    puts 'would reload changed services...'
    services.reload.each(&:reload)

    puts 'would restart changed services...'
    services.restart.each(&:start)

    puts 'runit would start new services...'
    services.start.each(&:start)

    activate_osctl(services)
  end

  def boot
    if INSTALL_BOOTLOADER == 'none'
      puts 'no bootloader active'
      return
    end

    system(INSTALL_BOOTLOADER, OUT) || (fail 'unable to install boot loader')
  end

  def switch
    boot
    test
  end

  def test
    puts 'probing runit services...'
    services = Services.new(**opts)

    puts 'probing pools...'
    pools = Pools.new(**opts)
    pools.export
    pools.rollback

    if pools.error.any?
      puts "unable to handle pools: #{pools.error.map(&:name).join(',')}"
    end

    puts 'stopping deprecated services...'
    services.stop.each(&:stop)

    puts 'stopping changed services...'
    services.restart.each(&:stop)

    puts 'activating the configuration...'
    activate

    services.switch_runlevel

    puts 'reloading changed services...'
    services.reload.each(&:reload)

    puts 'restarting changed services...'
    services.restart.each(&:start)

    puts 'runit will start new services...'

    activate_osctl(services)
  end

  def activate
    return if opts[:dry_run]
    system(File.join(OUT, 'activate'))
  end

  protected
  attr_reader :opts

  def activate_osctl(services)
    args = []

    if services.reload.detect { |s| s.name == 'lxcfs' }
      args << '--lxcfs'
    else
      args << '--no-lxcfs'
    end

    if services.restart.detect { |s| s.name == 'osctld' }
      # osctld has been restarted, so system files are already regenerated
      # and we just have to refresh LXCFS
      args << '--no-system'

      # It takes time for osctld to start
      wait_for_osctld

    else
      args << '--system'
    end

    puts "> osctl activate #{args.join(' ')}"
    return if opts[:dry_run]

    system(File.join(CURRENT_BIN, 'osctl'), 'activate', *args)
  end

  def wait_for_osctld
    if opts[:dry_run]
      puts 'would wait for osctld to start...'
      return
    end

    puts 'waiting for osctld to start...'
    system(File.join(CURRENT_BIN, 'osctl'), 'ping', '0')
  end
end

class Services
  Service = Struct.new(:name, :base_path, :cfg, :opts) do
    attr_reader :run_path, :on_change, :reload_method

    def initialize(*_)
      super

      @run_path = File.realpath(File.join(base_path, 'etc/runit/services', name, 'run'))
      @on_change = cfg['onChange'].to_sym
      @reload_method = cfg['reloadMethod']
    end

    def ==(other)
      run_path == other.run_path
    end

    %i(start stop restart).each do |m|
      define_method(m) do
        puts "> sv #{m} #{name}"

        unless opts[:dry_run]
          system(File.join(Configuration::CURRENT_BIN, 'sv'), m.to_s, name)
        end
      end
    end

    def reload
      puts "> sv #{reload_method} #{name}"

      unless opts[:dry_run]
        system(File.join(Configuration::CURRENT_BIN, 'sv'), reload_method, name)
      end
    end
  end

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}

    @old_cfg = read_cfg(File.join(Configuration::CURRENT_SYSTEM, '/services'))
    @new_cfg = read_cfg(File.join(Configuration::OUT, '/services'))

    @old_runlevel = File.basename(File.realpath('/service'))
    @new_runlevel = get_runlevel(@new_cfg, @old_runlevel)

    @old_services = get_services(@old_cfg, @old_runlevel, '/')
    @new_services = get_services(@new_cfg, @new_runlevel, Configuration::ETC)
  end

  # Services that are new and should be started
  # @return [Array<Service>]
  def start
    (new_services.keys - old_services.keys).map { |s| new_services[s] }
  end

  # Services that have been removed and should be stopped
  # @return [Array<Service>]
  def stop
    (old_services.keys - new_services.keys).map { |s| old_services[s] }
  end

  # Services that have been changed and should be restarted
  # @return [Array<Service>]
  def restart
    (old_services.keys & new_services.keys).select do |s|
      old_services[s] != new_services[s] && new_services[s].on_change == :restart
    end.map { |s| new_services[s] }
  end

  # Services that have been changed and should be reloaded
  # @return [Array<Service>]
  def reload
    (old_services.keys & new_services.keys).select do |s|
      old_services[s] != new_services[s] && new_services[s].on_change == :reload
    end.map { |s| new_services[s] }
  end

  def switch_runlevel
    return if old_runlevel == new_runlevel

    if opts[:dry_run]
      puts 'would switch runlevel...'
    else
      puts 'switching runlevel...'
    end

    puts "> runsvchdir #{new_runlevel}"
    return if opts[:dry_run]

    system(File.join(Configuration::CURRENT_BIN, 'runsvchdir'), new_runlevel)
  end

  protected
  attr_reader :old_cfg, :new_cfg
  attr_reader :old_services, :new_services
  attr_reader :old_runlevel, :new_runlevel
  attr_reader :opts

  # Parse service config
  # @param path [String]
  # @return [Hash]
  def read_cfg(path)
    JSON.parse(File.read(path))
  end

  # Return services from a selected runlevel
  # @param cfg [Hash] service config
  # @param runlevel [String] include only services from this runlevel
  # @param base_dir [String] absolute path to a directory containing the system's
  #                          `/etc`
  # @return [Hash<String, Service>]
  def get_services(cfg, runlevel, base_dir)
    ret = {}

    cfg['services'].each do |name, service|
      next unless service['runlevels'].include?(runlevel)

      begin
        ret[name] = Service.new(
          name,
          base_dir,
          service,
          opts,
        )

      rescue Errno::ENOENT
        warn "service '#{name}' not found"
        next
      end
    end

    ret
  end

  # Return target runlevel
  def get_runlevel(cfg, old_runlevel)
    if cfg['defaultRunlevel'] == old_runlevel
      old_runlevel

    elsif cfg['services'].map { |k,v| v['runlevels']}.flatten.include?(old_runlevel)
      old_runlevel

    else
      cfg['defaultRunlevel']
    end
  end
end

class Pools
  Pool = Struct.new(:name, :state, :rollback_version)

  attr_reader :uptodate, :to_upgrade, :to_rollback, :error

  def initialize(dry_run: true)
    @opts = {dry_run: dry_run}

    @uptodate = []
    @to_upgrade = []
    @to_rollback = []
    @error = []

    @old_pools = check(Configuration::CURRENT_BIN)
    @new_pools = check(Configuration::NEW_BIN)

    resolve
  end

  # Rollback pools using the current OS version, as the activated OS version
  # is older
  def rollback
    to_rollback.each do |pool|
      puts "> rolling back pool #{pool.name}"
      next if opts[:dry_run]

      ret = system(
        File.join(Configuration::CURRENT_BIN, 'osup'),
        'rollback', pool.name, pool.rollback_version
      )

      unless ret
        fail "rollback of pool #{pool.name} failed, cannot proceed"
      end
    end
  end

  # Export pools from osctld before upgrade
  #
  # This will stop all containers from outdated pools. We're counting on the
  # fact that if there are new migrations, then osctld has to have changed
  # as well, so it is restarted by {Services}. After restart, osctld will run
  # `osup upgrade` on all imported pools.
  def export
    (to_rollback + to_upgrade).each do |pool|
      puts "> exporting pool #{pool.name} to upgrade"
      next if opts[:dry_run]

      # TODO: do not fail if the pool is not imported
      ret = system(
        File.join(Configuration::CURRENT_BIN, 'osctl'),
        'pool', 'export', '-f', pool.name
      )

      unless ret
        fail "export of pool #{pool.name} failed, cannot proceed"
      end
    end
  end

  protected
  attr_reader :opts, :old_pools, :new_pools

  def resolve
    new_pools.each do |name, pool|
      case pool.state
      when :ok
        uptodate << pool

      when :outdated
        to_upgrade << pool

      when :incompatible
        if old_pools[name] && old_pools[name].state == :ok
          to_rollback << pool

        else
          error << pool
        end
      end
    end
  end

  def check(swbin)
    ret = {}

    IO.popen("#{File.join(swbin, 'osup')} check") do |io|
      io.each_line do |line|
        name, state, version = line.strip.split
        ret[name] = Pool.new(name, state.to_sym, version)
      end
    end

    ret

  rescue Errno::ENOENT
    # osup isn't available in the to-be-replaced OS version
    {}
  end
end

case ARGV[0]
when 'boot'
  Configuration.boot
when 'switch'
  Configuration.switch
when 'test'
  Configuration.test
when 'dry-activate'
  Configuration.dry_run
else
  warn "Usage: #{$0} switch|dry-activate"
  exit(false)
end
