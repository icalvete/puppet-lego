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
  exec { 'lego-extract':
    command => "/bin/tar -xzf ${staged} -C ${install_dir} lego && /bin/chmod 0755 ${binary}",
    unless  => "/bin/sh -c '${binary} --version 2>/dev/null | /bin/grep -q \"lego version ${version} \"'",
    require => File[$staged],
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
