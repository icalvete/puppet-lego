# == Define: lego::cert
#
# Un certificado. Declara el fichero de entorno, la unidad oneshot que lo pide
# o lo renueva, el temporizador que la lanza, y el deploy-hook que se ejecuta
# tras cada renovacion con exito.
#
# En lego 5.x 'run' obtiene Y renueva, asi que no hace falta ningun envoltorio
# que decida entre las dos cosas.
#
# === Parametros obligatorios
#   $domains          Lista de nombres. El primero es el CN; el resto, SAN.
#   $email            Correo de la cuenta ACME. La CA avisa ahi si una
#                     renovacion falla: que sea una direccion que alguien lea.
#   $hosted_zone_id   Zona de Route53 donde escribir el reto. Fijarla evita que
#                     lego autodetecte, y ahorra el permiso ListHostedZones.
#
# === Parametros para el caso cross-account
#   $assume_role_arn  Rol a asumir cuando la zona esta en OTRA cuenta. Route53
#                     no admite politicas basadas en recurso, asi que es la
#                     unica via. Si la zona esta en la cuenta del propio host,
#                     dejarlo en undef: bastan las credenciales del instance
#                     profile.
#
# === Despliegue del material
#   $deploy_cert      Ruta donde el hook deja el certificado (con su cadena)
#   $deploy_key       Ruta donde el hook deja la clave privada, en 0600
#   $deploy_chain     Opcional: ruta donde dejar solo la cadena del emisor
#   $reload_command   Que ejecutar despues. Ej: 'systemctl reload apache2'
#
# === Nombre de las unidades
#   $unit_name        Prefijo de la unidad, el temporizador, el fichero de
#                     entorno y el hook. Por defecto 'lego', para que el
#                     servicio se llame igual en toda la flota y cualquier
#                     runbook valga en cualquier maquina.
#
#                     Un host solo necesita un certificado si este cubre todos
#                     sus nombres. Si aun asi declaras dos lego::cert en el
#                     mismo host, Puppet fallara al compilar por recurso
#                     duplicado: ponle unit_name al segundo.
#
# Apuntando deploy_cert y deploy_key a las rutas que ya usa la configuracion del
# servidor web, migrar un host desde un certificado repartido por otros medios no
# obliga a tocar ningun vhost: basta cambiar de clase.
#
define lego::cert (
  $domains,
  $email,
  $hosted_zone_id,
  $assume_role_arn = undef,
  $deploy_cert     = undef,
  $deploy_key      = undef,
  $deploy_chain    = undef,
  $reload_command  = undef,
  $server          = $lego::params::server,
  $key_type        = $lego::params::key_type,
  $renew_days      = $lego::params::renew_days,
  $check_interval  = $lego::params::check_interval,
  $enable_timer    = $lego::params::enable_timer,
  $aws_region      = 'eu-west-1',
  $unit_name       = $lego::params::unit_name,
) {

  include lego

  if ! is_array($domains) or empty($domains) {
    fail("lego::cert[${name}]: domains tiene que ser una lista con al menos un nombre.")
  }
  if ! $email {
    fail("lego::cert[${name}]: falta email (la CA avisa ahi si la renovacion falla).")
  }
  if ! $hosted_zone_id {
    fail("lego::cert[${name}]: falta hosted_zone_id.")
  }
  # Desplegar el certificado sin la clave, o al reves, deja un vhost roto.
  if ($deploy_cert and ! $deploy_key) or ($deploy_key and ! $deploy_cert) {
    fail("lego::cert[${name}]: deploy_cert y deploy_key van juntos o no van.")
  }

  $primary   = $domains[0]
  $unit      = $unit_name
  $env_file  = "${lego::conf_dir}/${unit_name}.env"
  $hook_file = "${lego::hook_dir}/${unit_name}-deploy"

  # El fichero de entorno lleva TODA la configuracion: cada opcion de lego
  # tiene su variable LEGO_*, asi que la unidad no necesita argumentos.
  # 0600 porque nombra el rol y la zona.
  file { $env_file:
    ensure  => present,
    content => template("${module_name}/cert.env.erb"),
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    require => Class['lego::install'],
    notify  => Exec['lego-systemd-daemon-reload'],
  }

  # El hook lo ejecuta LEGO tras renovar, no Puppet. Por eso la recarga del
  # servicio es un comando dentro del script y no un recurso de Puppet.
  file { $hook_file:
    ensure  => present,
    content => template("${module_name}/deploy-hook.sh.erb"),
    owner   => 'root',
    group   => 'root',
    mode    => '0700',
    require => Class['lego::install'],
  }

  file { "/etc/systemd/system/${unit}.service":
    ensure  => present,
    content => template("${module_name}/lego.service.erb"),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => [File[$env_file], File[$hook_file]],
    notify  => Exec['lego-systemd-daemon-reload'],
  }

  file { "/etc/systemd/system/${unit}.timer":
    ensure  => present,
    content => template("${module_name}/lego.timer.erb"),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => File["/etc/systemd/system/${unit}.service"],
    notify  => Exec['lego-systemd-daemon-reload'],
  }

  # enable_timer=false deja el timer instalado y PARADO: nada se pide hasta que
  # alguien lo arranque a mano. El service es oneshot, asi que arrancarlo es
  # hacer el proceso completo una vez, y se ve entero en el journal.
  service { "${unit}.timer":
    ensure    => $enable_timer ? { true => running, default => stopped },
    enable    => $enable_timer,
    subscribe => File["/etc/systemd/system/${unit}.timer"],
    require   => Exec['lego-systemd-daemon-reload'],
  }
}
