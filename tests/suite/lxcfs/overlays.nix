import ../../make-template.nix ({ distribution, version }: rec {
  instance = "${distribution}-${version}";

  test = pkgs: {
    name = "lxcfs-overlays@${instance}";

    description = ''
      Test LXCFS is mounted in containers with ${distribution}-${version}
    '';

    machine = import ../../machines/tank.nix pkgs;

    testScript = ''
      machine.wait_for_osctl_pool("tank")
      machine.wait_until_online

      machine.all_succeed(
        "osctl ct new --distribution ${distribution} --version ${version} testct",
        "osctl ct start testct",
      )

      _, output = machine.succeeds("osctl ct exec testct cat /proc/mounts")

      be_mounted = %w(
        /proc/cpuinfo
        /proc/diskstats
        /proc/loadavg
        /proc/stat
        /proc/uptime
        /sys/devices/system/cpu/online
      )

      be_unmounted = %w(
        /proc/meminfo
        /proc/swaps
      )

      be_mounted.each do |f|
        if /^lxcfs #{Regexp.escape(f)} fuse\.lxcfs / !~ output
          fail "#{f} not mounted"
        end
      end

      be_unmounted.each do |f|
        if /^lxcfs #{Regexp.escape(f)} fuse\.lxcfs / =~ output
          fail "#{f} mounted"
        end
      end
    '';
  };
})
