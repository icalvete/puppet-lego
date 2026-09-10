# == Class: lego
#
# Instala el cliente ACME lego. No pide ningun certificado por si sola: para
# eso se declara un lego::cert por cada certificado que el host necesite.
#
# El binario viene vendorizado en files/ y no del paquete de la distribucion:
# Ubuntu 22.04 trae la 4.1.3, de 2020, que no soporta AWS_ASSUME_ROLE_ARN y por
# tanto no puede resolver retos DNS-01 contra una zona de otra cuenta.
#
# === Parametros
#   $version      Version vendorizada. Debe existir
#                 files/lego_v${version}_linux_amd64.tar.gz
#   $install_dir  Donde se instala el binario
#   $data_dir     Donde lego guarda cuentas y certificados ($LEGO_PATH)
#   $manage_data_dir  false para hornear una AMI: instala el binario y no crea
#                 el arbol de datos
#
# === Ejemplo
#   include lego
#
#   lego::cert { 'www':
#     domains        => ['www.example.com', 'example.com'],
#     email          => 'admin@example.com',
#     hosted_zone_id => 'Z0EXAMPLE1234567',
#     deploy_cert    => '/etc/ssl/certs/example.crt',
#     deploy_key     => '/etc/ssl/private/example.key',
#     reload_command => 'systemctl reload apache2',
#   }
#
# Si la zona esta en OTRA cuenta de AWS que el host, hace falta asumir un rol,
# porque Route53 no admite politicas basadas en recurso:
#
#     assume_role_arn => 'arn:aws:iam::123456789012:role/acme-dns01',
#
class lego (
  $version         = $lego::params::version,
  $install_dir     = $lego::params::install_dir,
  $data_dir        = $lego::params::data_dir,
  $conf_dir        = $lego::params::conf_dir,
  $hook_dir        = $lego::params::hook_dir,
  $manage_data_dir = true,
) inherits lego::params {

  anchor { 'lego::begin':
    before => Class['lego::install'],
  }

  class { 'lego::install':
    require => Anchor['lego::begin'],
  }

  anchor { 'lego::end':
    require => Class['lego::install'],
  }

  # Un daemon-reload propio, con nombre unico. Los modulos de este repo
  # referencian Exec['systemctl-daemon-reload'], que no se declara en ninguno
  # de ellos; depender de eso ataria este modulo a un entorno concreto.
  exec { 'lego-systemd-daemon-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
  }
}
