import ./base.nix {
  distribution = "ubuntu";
  version = "20.04";
  setupScript = ''
    machine.all_succeed(
      "osctl ct exec docker apt-get update -y",
      "osctl ct exec docker apt-get -y install apt-transport-https ca-certificates curl software-properties-common",
      "osctl ct exec docker bash -c \"curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -\"",
      "osctl ct exec docker add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable\"",
      "osctl ct exec docker apt-get update -y",
      "osctl ct exec docker apt-get -y install docker-ce",
    )
  '';
}
