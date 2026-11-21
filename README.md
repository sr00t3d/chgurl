# chgurl — Multi-CMS URL & Domain Changer (`chgurl.sh`)

🇺🇸 **English** | 🇧🇷 [Português (BR)](README-ptbr.md) | 🇪🇸 [Español](README-es.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/chgurl/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

`chgurl.sh` is a Bash CLI for safely updating site URLs and domains across **WordPress**, **Magento 1 & 2**, **PrestaShop 1.6 / 1.7 / 8**, **WHMCS**, **Joomla**, and **Drupal** — with automatic CMS detection (`--auto`), `chmod 600` SQL/config backups, `--dry-run` previews, and structured `table`, `json`, and `csv` outputs.

> **Historical Credits:** Originally drafted in 2012 during the HostGator era by **Percio Andrade (Percio Castelo)** with contributions from **Jose Terra** and **Leonardo Bolsoni**, now completed, hardened, and modernized for production sysadmin workflows.

## Key Features

- **6 CMS Platforms + Auto-Detection (`--auto`):**
  - **WordPress (`-w`):** parses `wp-config.php` (including custom `$table_prefix`), updates `options`, `posts`, `postmeta`, and `comments`.
  - **Magento 1 & 2 (`-m`):** supports `app/etc/local.xml` and `app/etc/env.php`, updates `web/unsecure/base_url` and `web/secure/base_url` with trailing `/`, and clears `var/cache` & `var/session`.
  - **PrestaShop 1.6 / 1.7 / 8 (`-p`):** supports `config/settings.inc.php` and `app/config/parameters.php`, updates `PS_SHOP_DOMAIN`, `PS_SHOP_DOMAIN_SSL`, and `shop_url`.
  - **WHMCS (`-s`):** parses `configuration.php` and updates `Domain` and `SystemURL` in `tblconfiguration`.
  - **Joomla (`-j`):** updates `$live_site` in `configuration.php` safely without external legacy tools.
  - **Drupal (`-l`):** uncomments/updates `$base_url` in `sites/default/settings.php`.
- **Safe Database & File Operations:** authenticates to MySQL/MariaDB via temporary `chmod 600` `--defaults-extra-file` (properly escaping `#` and quotes), creates `chmod 600` `.sql.gz` or `.bak` backups before any write, and supports `--dry-run` row/file previews.
- **cPanel Integration (`-d, --domain`):** optionally resolves the primary domain from `/etc/trueuserdomains`.

## Installation

```bash
git clone https://github.com/sr00t3d/chgurl.git
cd chgurl
chmod +x chgurl.sh
sudo install -m 0755 chgurl.sh /usr/local/bin/chgurl
```

## Usage

```bash
# Auto-detect CMS and preview changes (--dry-run)
chgurl --auto --dir /home/user/public_html --dry-run newsite.example.com

# WordPress live update with automatic chmod 600 SQL backup and JSON output
chgurl -w --dir /home/user/public_html --yes -o json newsite.example.com

# WHMCS live update in CSV format
chgurl -s --dir /var/www/whmcs --yes -o csv billing.example.com

# Magento 2 with HTTP scheme override
chgurl -m --dir /var/www/magento --scheme http --yes staging.example.com

# Joomla / Drupal config update
chgurl -j --dir /var/www/joomla --yes portal.example.com
chgurl -l --dir /var/www/drupal --yes drupal.example.com
```

## Real Output Example

### WordPress Auto-Detect Dry-Run (`chgurl.sh --auto --dir /path/to/wp --dry-run --no-color newsite.example.com`)

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

### WordPress Live Execution in JSON (`chgurl.sh --auto --dir /path/to/wp --yes -o json newsite.example.com`)

```json
{
  "tool": "chgurl.sh",
  "version": "2.0.0",
  "timestamp": "2026-11-21T00:32:12Z",
  "cms": "wordpress",
  "config_file": "/tmp/chgurl-e2e/wp/wp-config.php",
  "database": "chgurl_e2e_wp",
  "old_url": "http://oldsite.example.com",
  "new_url": "https://newsite.example.com",
  "rows_or_files_affected": 6,
  "backup_path": "/tmp/chgurl-e2e/backups/chgurl-wordpress-chgurl_e2e_wp-20261121-003212.sql.gz",
  "dry_run": false,
  "status": "updated"
}
```

## Credits & License

- **Original Author (2012):** Percio Andrade (Percio Castelo)
- **Original Contributors (2012):** Jose Terra, Leonardo Bolsoni
- **License:** [Apache License 2.0](LICENSE)
