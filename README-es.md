# chgurl — Cambiador de URL y Dominio Multi-CMS (`chgurl.sh`)

🇺🇸 [English](README.md) | 🇧🇷 [Português (BR)](README-ptbr.md) | 🇪🇸 **Español**

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/chgurl/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

`chgurl.sh` es una CLI en Bash para actualizar URLs y dominios de forma segura en **WordPress**, **Magento 1 y 2**, **PrestaShop 1.6 / 1.7 / 8**, **WHMCS**, **Joomla** y **Drupal** — con detección automática de CMS (`--auto`), copias de seguridad SQL/config con `chmod 600`, vista previa `--dry-run` y salidas estructuradas en `table`, `json` y `csv`.

> **Créditos Históricos:** Iniciado originalmente en 2012 (etapa HostGator) por **Percio Andrade (Percio Castelo)** con contribuciones de **Jose Terra** y **Leonardo Bolsoni**, ahora completado, endurecido y modernizado para entornos de producción.

## Características Principales

- **6 Plataformas CMS + Detección Automática (`--auto`):**
  - **WordPress (`-w`):** analiza `wp-config.php` (incluyendo `$table_prefix` personalizado) y actualiza `options`, `posts`, `postmeta` y `comments`.
  - **Magento 1 y 2 (`-m`):** compatible con `app/etc/local.xml` y `app/etc/env.php`, actualiza `web/unsecure/base_url` y `web/secure/base_url` con `/` final y limpia `var/cache` y `var/session`.
  - **PrestaShop 1.6 / 1.7 / 8 (`-p`):** compatible con `config/settings.inc.php` y `app/config/parameters.php`, actualiza `PS_SHOP_DOMAIN`, `PS_SHOP_DOMAIN_SSL` y `shop_url`.
  - **WHMCS (`-s`):** analiza `configuration.php` y actualiza `Domain` y `SystemURL` en `tblconfiguration`.
  - **Joomla (`-j`):** actualiza `$live_site` en `configuration.php` sin herramientas obsoletas.
  - **Drupal (`-l`):** descomenta y actualiza `$base_url` en `sites/default/settings.php`.
- **Seguridad en Base de Datos y Archivos:** autenticación MySQL/MariaDB mediante `--defaults-extra-file` temporal `chmod 600`, respaldos automáticos `.sql.gz` o `.bak` (`chmod 600`) antes de modificar nada y modo `--dry-run`.
- **Integración cPanel (`-d, --domain`):** resuelve automáticamente el dominio principal desde `/etc/trueuserdomains`.

## Instalación

```bash
git clone https://github.com/sr00t3d/chgurl.git
cd chgurl
chmod +x chgurl.sh
sudo install -m 0755 chgurl.sh /usr/local/bin/chgurl
```

## Uso

```bash
# Detectar CMS automáticamente y previsualizar cambios (--dry-run)
chgurl --auto --dir /home/user/public_html --dry-run newsite.example.com

# Actualización real en WordPress con respaldo SQL chmod 600 y salida JSON
chgurl -w --dir /home/user/public_html --yes -o json newsite.example.com

# Actualización real en WHMCS en formato CSV
chgurl -s --dir /var/www/whmcs --yes -o csv billing.example.com
```

## Ejemplo de Salida Real

### Vista Previa Dry-Run en WordPress (`chgurl.sh --auto --dir /path/to/wp --dry-run --no-color newsite.example.com`)

```text
=====================================================================
 chgurl.sh v2.0.0 | CMS: wordpress | 2026-11-21T00:32:12Z
=====================================================================
  CMS Detected  : wordpress (/tmp/chgurl-e2e/wp/wp-config.php)
  Database      : chgurl_e2e_wp (prefix: wp_e2e_)
  Old URL       : http://oldsite.example.com
  New URL       : https://newsite.example.com
  Affected      : 5
  Backup        : none
  Status        : dry-run-preview
```

## Créditos y Licencia

- **Autor Original (2012):** Percio Andrade (Percio Castelo)
- **Contribuidores Originales (2012):** Jose Terra, Leonardo Bolsoni
- **Licencia:** [Apache License 2.0](LICENSE)
