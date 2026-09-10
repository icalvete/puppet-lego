# == Class: lego::params
#
# Valores por defecto. No se declara directamente.
#
class lego::params {

  # Version vendorizada en files/. Cambiarla implica subir el tar.gz nuevo.
  $version = '5.4.1'

  $install_dir = '/usr/local/bin'
  $data_dir    = '/etc/lego'
  $conf_dir    = '/etc/lego/conf.d'
  $hook_dir    = '/usr/local/sbin'

  # RSA2048 explicito: lego usa EC256 (ECDSA P-256) por defecto, y eso es un
  # cambio de algoritmo respecto a lo que hay hoy. ECDSA es mas fuerte y mas
  # barato en handshake, pero esta pospuesto hasta que el equipo del SDK
  # reporte sus pruebas de compatibilidad. Cambiarlo es una palabra.
  $key_type = 'RSA2048'

  # Atajos que entiende lego: 'letsencrypt-staging' y 'letsencrypt'.
  # Staging emite certificados que ningun navegador se cree, pero sus limites
  # son mucho mas altos: es donde se depura la configuracion sin gastar cupo.
  $server = 'letsencrypt-staging'

  # Cada cuanto se COMPRUEBA si toca renovar (no cada cuanto se renueva).
  $check_interval = '12h'

  # Con 0, lego decide solo: 1/3 de la vida restante del certificado, o la
  # mitad si es de vida corta. Y usa ARI (RFC9773) para que la propia CA le
  # diga cuando. Mejor que fijar un numero a mano.
  $renew_days = 0

  # false → Puppet deja el timer parado. La primera emision se lanza a mano,
  # mirando el journal, que es cuando se descubren los errores de permisos.
  $enable_timer = false
}
