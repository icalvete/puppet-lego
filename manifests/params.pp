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

  # 30 dias de margen sobre una vida de 90.
  #
  # NO se deja en 0 aunque la ayuda de lego diga que 0 significa "calcula
  # dinamicamente: 1/3 de la vida restante". Comprobado contra lego 5.4.1 sobre
  # un certificado real con 86 dias por delante:
  #
  #   LEGO_RENEW_DAYS=0    -> "renewal can be performed in 86d22h"  = AL CADUCAR
  #   LEGO_RENEW_DAYS=30   -> "renewal can be performed in 56d22h"  = 30d antes
  #
  # Con ARI activado y desactivado sale igual, asi que no es cosa de ARI: el 0
  # se aplica literalmente y la ventana de renovacion se abre en el instante de
  # la caducidad. Con el timer comprobando cada 12h, eso son hasta 12 horas
  # sirviendo un certificado caducado, y cero margen si la renovacion falla.
  $renew_days = 30

  # Prefijo de las unidades de systemd. Se deja fijo y no derivado del titulo
  # del recurso para que el servicio se llame igual en todas las maquinas: un
  # nombre distinto por host obliga a saber cual antes de poder operarlo.
  $unit_name = 'lego'

  # false → Puppet deja el timer parado. La primera emision se lanza a mano,
  # mirando el journal, que es cuando se descubren los errores de permisos.
  $enable_timer = false
}
