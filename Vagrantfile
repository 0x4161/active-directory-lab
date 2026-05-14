# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Active Directory Attack Lab
# https://github.com/0x4161/active-directory-lab
#
# Usage:
#   vagrant plugin install vagrant-reload
#   vagrant up
#
# VMs built:
#   DC01  192.168.56.10  corp.local (Forest Root DC + CA)
#   DC02  192.168.56.20  dev.corp.local (Child Domain DC)
#   WS01  192.168.56.30  Attacker Workstation

unless Vagrant.has_plugin?("vagrant-reload")
  abort <<~MSG

    [!] Required plugin missing: vagrant-reload
        Install it with:  vagrant plugin install vagrant-reload
        Then run:         vagrant up

  MSG
end

Vagrant.configure("2") do |config|

  config.vm.boot_timeout          = 900
  config.vm.graceful_halt_timeout = 180
  config.vm.communicator          = "winrm"
  config.winrm.username           = "vagrant"
  config.winrm.password           = "vagrant"
  config.winrm.timeout            = 300
  config.winrm.retry_limit        = 20

  # ── DC-01 : Forest Root DC + CA (corp.local) ────────────────────────────────
  config.vm.define "dc01", primary: true do |m|
    m.vm.box      = "StefanScherer/windows_2019"
    m.vm.hostname = "DC-01"
    m.vm.network "private_network", ip: "192.168.56.10"

    m.vm.provider "virtualbox" do |vb|
      vb.name   = "AD-Lab-DC01"
      vb.memory = 4096
      vb.cpus   = 2
      vb.gui    = false
      vb.customize ["modifyvm", :id, "--groups", "/AD-Lab"]
    end

    # 1. Promote to Forest Root DC
    m.vm.provision "shell",
      path:       "vagrant/provision-dc01.ps1",
      privileged: true

    # 2. Reboot after promotion
    m.vm.provision "reload"

    # 3. Configure corp.local (users, groups, ACLs, ADCS, misconfigs)
    m.vm.provision "shell",
      path:       "scripts/Setup-CorpLocal.ps1",
      privileged: true
  end

  # ── DC-02 : Child Domain DC (dev.corp.local) ─────────────────────────────────
  config.vm.define "dc02" do |m|
    m.vm.box      = "StefanScherer/windows_2019"
    m.vm.hostname = "DC-02"
    m.vm.network "private_network", ip: "192.168.56.20"

    m.vm.provider "virtualbox" do |vb|
      vb.name   = "AD-Lab-DC02"
      vb.memory = 4096
      vb.cpus   = 2
      vb.gui    = false
      vb.customize ["modifyvm", :id, "--groups", "/AD-Lab"]
    end

    # 1. Set DNS to DC01 + Promote to Child Domain
    m.vm.provision "shell",
      path:       "vagrant/provision-dc02.ps1",
      privileged: true

    # 2. Reboot after promotion
    m.vm.provision "reload"

    # 3. Configure dev.corp.local
    m.vm.provision "shell",
      path:       "scripts/Setup-DevCorpLocal.ps1",
      privileged: true
  end

  # ── WS-01 : Attacker Workstation ─────────────────────────────────────────────
  config.vm.define "ws01" do |m|
    m.vm.box      = "gusztavvargadr/windows-10"
    m.vm.hostname = "WS-01"
    m.vm.network "private_network", ip: "192.168.56.30"

    m.vm.provider "virtualbox" do |vb|
      vb.name   = "AD-Lab-Attacker"
      vb.memory = 4096
      vb.cpus   = 2
      vb.gui    = true
      vb.customize ["modifyvm", :id, "--groups", "/AD-Lab"]
    end

    # 1. Set DNS + Join corp.local
    m.vm.provision "shell",
      path:       "vagrant/provision-ws01.ps1",
      privileged: true

    # 2. Reboot after domain join
    m.vm.provision "reload"
  end

end
