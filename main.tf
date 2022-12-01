# ./main.tf

module "aws_network" {
  for_each = { for network in local.networks : network.id => network if network.aws != null }
  source   = "git::https://github.com/labrats-work/modules-terraform.git//modules/aws/network?ref=main"

  network_name          = each.value.aws.name
  network_ip_range      = each.value.aws.ip_range
  network_subnet_ranges = each.value.aws.subnet_ranges
}

module "cloud-init" {
  for_each = { for node in local.nodes : node.id => node if node.aws != null }
  source   = "git::https://github.com/labrats-work/modules-terraform.git//modules/cloud-init?ref=main"
  general = {
    hostname                   = each.value.aws.name
    package_reboot_if_required = true
    package_update             = true
    package_upgrade            = true
    timezone                   = "Europe/Warsaw"
  }
  users_data = [
    {
      name  = "sysadmin"
      shell = "/bin/bash"
      ssh-authorized-keys = [
        var.public_key,
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILDxJpolhuDKTr4KpXnq5gPTKYUnoKyAnpIR4k5m3XCH u0@prt-dev-01"
      ]
    }
  ]
  runcmd = [
    "mkdir -p /etc/ssh/sshd_config.d",
    "echo \"Port 2222\" > /etc/ssh/sshd_config.d/90-defaults.conf"
  ]
}

module "aws_nodes" {
  for_each = { for node in local.nodes : node.id => node if node.aws != null }

  source               = "git::https://github.com/labrats-work/modules-terraform.git//modules/aws/node?ref=main"
  node_config          = each.value.aws
  subnet_id            = values(module.aws_network)[0].hetzner_subnets["10.98.0.0/24"].id
  cloud_init_user_data = module.cloud-init[each.key].user_data
}

resource "local_file" "ansible_inventory" {
  content  = <<-EOT
[master]
%{for node in module.aws_nodes~}
%{if node.nodetype == "master"}${~node.name} ansible_host=${node.ipv4_address}%{endif}
%{~endfor~}

[worker]
%{for node in module.aws_nodes~}
%{if node.nodetype == "worker"}${~node.name} ansible_host=${node.ipv4_address}%{endif}
%{~endfor~}

[haproxy]
%{for node in module.aws_nodes~}
%{if node.nodetype == "haproxy"}${~node.name} ansible_host=${node.ipv4_address}%{endif}
%{~endfor~}

[bastion]
%{for node in module.aws_nodes~}
%{if node.nodetype == "bastion"}${~node.name} ansible_host=${node.ipv4_address}%{endif}
%{~endfor~}
  EOT
  filename = "ansible/inventory"
}