# == Class: lego::install
#
# Coloca el tar.gz vendorizado y extrae el binario.
#
# Se vendoriza el tar.gz y no el binario suelto porque el binario extraido son
# 68 MB y el tar.gz 21: tres veces menos en el repositorio por cada version.
#
class lego::install {

  $version     = $lego::version
  $install_dir = $lego::install_dir
  $data_dir    = $lego::data_dir
  $conf_dir    = $lego::conf_dir
  $tarball     = "lego_v${version}_linux_amd64.tar.gz"
  $staged      = "/opt/${tarball}"
  $binary      = "${install_dir}/lego"

  file { $staged:
    ensure => present,
    source => "puppet:///modules/${module_name}/${tarball}",
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
  }

  # El unless compara la version instalada, asi que extrae en la primera
  # pasada y cuando se sube una version nueva, y no hace nada el resto del
  # tiempo. Sin depender del modulo archive ni de staging.
  # --no-same-owner: extrayendo como root, tar conserva por defecto el uid/gid
  # que venga dentro del tar.gz. El de upstream trae 1001, que en la mayoria de
  # maquinas no existe. Un binario que systemd ejecuta como root no puede ser
  # propiedad de un uid arbitrario: el dia que se cree un usuario y le toque ese
  # numero, hereda la capacidad de reescribirlo.
  exec { 'lego-extract':
    command => "/bin/tar --no-same-owner -xzf ${staged} -C ${install_dir} lego",
    unless  => "/bin/sh -c '${binary} --version 2>/dev/null | /bin/grep -q \"lego version ${version} \"'",
    require => File[$staged],
  }

  # El propietario y los permisos se fijan aqui y no en el exec porque el exec
  # no vuelve a ejecutarse cuando la version ya es la correcta: en una maquina
  # que instalo una version anterior del modulo, el chmod del exec no llegaria
  # nunca. Sin source ni content, este recurso gestiona solo los metadatos y no
  # toca el contenido del binario.
  file { $binary:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Exec['lego-extract'],
  }

  if $lego::manage_data_dir {
    # 0700. Los subdirectorios por servidor ACME los crea lego::cert, y dentro
    # de cada uno lego crea accounts/ y certificates/ por su cuenta.
    file { $data_dir:
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      require => Exec['lego-extract'],
    }

    file { $conf_dir:
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      require => File[$data_dir],
    }
  }
}
