# Configure the node
#
# === Parameters:
#
# $parent_fqdn::                    fqdn of the parent node. REQUIRED
#
# $certs_tar::                      path to a tar with certs for the node
#
# $pulp::                           should Pulp be configured on the node
#                                   type:boolean
#
# $pulp_admin_password::            passowrd for the Pulp admin user.It should be left blank so that random password is generated
#                                   type:password
#
# $pulp_oauth_effective_user::      User to be used for Pulp REST interaction
#
# $pulp_oauth_key::                 OAuth key to be used for Pulp REST interaction
#
# $pulp_oauth_secret::              OAuth secret to be used for Pulp REST interaction
#
# $foreman_proxy_port::             Port on which will foreman proxy listen
#                                   type:integer
#
# $puppet::                         Use puppet
#                                   type:boolean
#
# $puppetca::                       Use puppet ca
#                                   type:boolean
#
# $tftp::                           Use TFTP
#                                   type:boolean
#
# $tftp_servername::                Defines the TFTP server name to use, overrides the name in the subnet declaration
#
# $dhcp::                           Use DHCP
#                                   type:boolean
#
# $dhcp_interface::                 DHCP listen interface
#
# $dhcp_gateway::                   DHCP pool gateway
#
# $dhcp_range::                     Space-separated DHCP pool range
#
# $dhcp_nameservers::               DHCP nameservers
#
# $dns::                            Use DNS
#                                   type:boolean
#
# $dns_zone::                       DNS zone name
#
# $dns_reverse::                    DNS reverse zone name
#
# $dns_interface::                  DNS interface
#
# $dns_forwarders::                 DNS forwarders
#                                   type:array
#
# $register_in_foreman::            Register proxy back in Foreman
#                                   type:boolean
#
# $foreman_oauth_effective_user::   User to be used for Foreman REST interaction
#
# $foreman_oauth_key::              OAuth key to be used for Foreman REST interaction
#
# $foreman_oauth_secret::           OAuth secret to be used for Foreman REST interaction
#
#
class katello_installer::node (
  $parent_fqdn                   = $katello_installer::params::parent_fqdn,
  $certs_tar                     = $katello_installer::params::certs_tar,
  $pulp                          = $katello_installer::params::pulp,
  $pulp_admin_password           = $katello_installer::params::pulp_admin_password,
  $pulp_oauth_effective_user     = $katello_installer::params::pulp_oauth_effective_user,
  $pulp_oauth_key                = $katello_installer::params::pulp_oauth_key,
  $pulp_oauth_secret             = $katello_installer::params::pulp_oauth_secret,

  $foreman_proxy_port            = $katello_installer::params::foreman_proxy_port,

  $puppet                        = $katello_installer::params::puppet,
  $puppetca                      = $katello_installer::params::puppetca,

  $tftp                          = $katello_installer::params::tftp,
  $tftp_servername               = $katello_installer::params::tftp_servername,

  $dhcp                          = $katello_installer::params::dhcp,
  $dhcp_interface                = $katello_installer::params::dhcp_interface,
  $dhcp_gateway                  = $katello_installer::params::dhcp_gateway,
  $dhcp_range                    = $katello_installer::params::dhcp_range,
  $dhcp_nameservers              = $katello_installer::params::dhcp_nameservers,

  $dns                           = $katello_installer::params::dns,
  $dns_zone                      = $katello_installer::params::dns_zone,
  $dns_reverse                   = $katello_installer::params::dns_reverse,
  $dns_interface                 = $katello_installer::params::dns_interface,
  $dns_forwarders                = $katello_installer::params::dns_forwarders,

  $register_in_foreman           = $katello_installer::params::register_in_foreman,
  $foreman_oauth_effective_user  = $katello_installer::params::foreman_oauth_effective_user,
  $foreman_oauth_key             = $katello_installer::params::foreman_oauth_key,
  $foreman_oauth_secret          = $katello_installer::params::foreman_oauth_secret
  ) inherits katello_installer::params {

  validate_present($parent_fqdn)

  if $pulp {
    validate_pulp($pulp)
    validate_present($pulp_oauth_secret)
  }

  $foreman_url = "https://$parent_fqdn/foreman"

  if $certs_tar {
    certs::tar_extract { $certs_tar:
      before => Class['certs']
    }
  }

  if $register_in_foreman {
    validate_present($foreman_oauth_secret)
  }

  if $parent_fqdn == $fqdn {
    # we are installing node features on the master
    $certs_generate = true
  } else {
    $certs_generate = false
  }

  class { 'certs': generate => $certs_generate, deploy   => true }

  if $pulp {
    class { 'certs::apache': }
    class { 'pulp':
      default_password => $pulp_admin_password,
      oauth_key        => $pulp_oauth_key,
      oauth_secret     => $pulp_oauth_secret
    }
    class { 'pulp::child':
      parent_fqdn          => $parent_fqdn,
      oauth_effective_user => $pulp_oauth_effective_user,
      oauth_key            => $pulp_oauth_key,
      oauth_secret         => $pulp_oauth_secret
    }
    katello_node { "https://${parent_fqdn}/katello":
      content => $pulp
    }
  }

  if $puppet {
    class { 'certs::puppet': } ~>

    class { puppet:
      server                      => true,
      server_foreman_url          => $foreman_url,
      server_foreman_ssl_cert     => $::certs::puppet::client_cert,
      server_foreman_ssl_key      => $::certs::puppet::client_key,
      server_foreman_ssl_ca       => $::certs::puppet::client_ca,
      server_storeconfigs_backend => false,
      server_dynamic_environments => true,
      server_environments_owner   => 'apache',
      server_config_version       => ''
    }
  }


  if $tftp or $dhcp or $dns or $puppet or $puppetca {

    if $certs_generate {
      # we make sure the certs for foreman are properly deployed
      class { 'certs::foreman':
        hostname => $parent_fqdn,
        deploy   => true,
        before     => Service['foreman-proxy'],
      }
    }

    class { 'certs::foreman_proxy':
      require    => Package['foreman-proxy'],
      before     => Service['foreman-proxy'],
    }

    class { foreman_proxy:
      custom_repo           => true,
      port                  => $foreman_proxy_port,
      puppetca              => $puppetca,
      ssl_cert              => $::certs::foreman_proxy::proxy_cert,
      ssl_key               => $::certs::foreman_proxy::proxy_key,
      ssl_ca                => $::certs::foreman_proxy::proxy_ca,
      tftp                  => $tftp,
      tftp_servername       => $tftp_servername,
      dhcp                  => $dhcp,
      dhcp_interface        => $dhcp_interface,
      dhcp_gateway          => $dhcp_gateway,
      dhcp_range            => $dhcp_range,
      dhcp_nameservers      => $dhcp_nameservers,
      dns                   => $dns,
      dns_zone              => $dns_zone,
      dns_reverse           => $dns_reverse,
      dns_interface         => $dns_interface,
      dns_forwarders        => $dns_forwarders,
      register_in_foreman   => $register_in_foreman,
      foreman_base_url      => $foreman_url,
      registered_proxy_url  => "https://${fqdn}:${foreman_proxy_port}",
      oauth_effective_user  => $foreman_oauth_effective_user,
      oauth_consumer_key    => $foreman_oauth_key,
      oauth_consumer_secret => $foreman_oauth_secret
    }
  }
}
