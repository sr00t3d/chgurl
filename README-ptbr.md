# chgurl — Alterador de URL e Domínio Multi-CMS (`chgurl.sh`)

🇺🇸 [English](README.md) | 🇧🇷 **Português (BR)** | 🇪🇸 [Español](README-es.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/sr00t3d/chgurl/releases) [![Shell](https://img.shields.io/badge/bash-4.0+-blue.svg)](https://www.gnu.org/software/bash/)

![Capa chgurl](chgurl-cover.webp)

`chgurl.sh` é uma CLI em Bash para alterar URLs e domínios com segurança em **WordPress**, **Magento 1 e 2**, **PrestaShop 1.6 / 1.7 / 8**, **WHMCS**, **Joomla** e **Drupal** — com detecção automática de CMS (`--auto`), backups SQL/config `chmod 600`, prévia `--dry-run` e saídas estruturadas em `table`, `json` e `csv`.

> **Créditos Históricos:** Originalmente iniciado em 2012 (era HostGator) por **Percio Andrade (Percio Castelo)** com contribuições de **Jose Terra** e **Leonardo Bolsoni**, agora finalizado, endurecido e modernizado para rotinas de produção.

## Principais Recursos

- **6 Plataformas CMS + Auto-Detecção (`--auto`):**
  - **WordPress (`-w`):** lê `wp-config.php` (incluindo `$table_prefix` customizado) e atualiza `options`, `posts`, `postmeta` e `comments`.
  - **Magento 1 e 2 (`-m`):** suporta `app/etc/local.xml` e `app/etc/env.php`, atualiza `web/unsecure/base_url` e `web/secure/base_url` com `/` final e limpa `var/cache` e `var/session`.
  - **PrestaShop 1.6 / 1.7 / 8 (`-p`):** suporta `config/settings.inc.php` e `app/config/parameters.php`, atualiza `PS_SHOP_DOMAIN`, `PS_SHOP_DOMAIN_SSL` e `shop_url`.
  - **WHMCS (`-s`):** lê `configuration.php` e atualiza `Domain` e `SystemURL` em `tblconfiguration`.
  - **Joomla (`-j`):** atualiza `$live_site` em `configuration.php` sem depender do utilitário legado `replace`.
  - **Drupal (`-l`):** descomenta e atualiza `$base_url` em `sites/default/settings.php`.
- **Segurança de Banco e Arquivos:** autenticação no MySQL/MariaDB via `--defaults-extra-file` temporário `chmod 600` (com escape de `#` e aspas), backup automático `.sql.gz` ou `.bak` com `chmod 600` antes de qualquer escrita e modo `--dry-run`.
- **Integração cPanel (`-d, --domain`):** detecta automaticamente o domínio principal via `/etc/trueuserdomains`.

## Instalação

```bash
git clone https://github.com/sr00t3d/chgurl.git
cd chgurl
chmod +x chgurl.sh
sudo install -m 0755 chgurl.sh /usr/local/bin/chgurl
```

## Uso

```bash
# Detectar CMS automaticamente e simular alterações (--dry-run)
chgurl --auto --dir /home/user/public_html --dry-run newsite.example.com

# Atualização real no WordPress com backup SQL chmod 600 e saída JSON
chgurl -w --dir /home/user/public_html --yes -o json newsite.example.com

# Atualização real no WHMCS em CSV
chgurl -s --dir /var/www/whmcs --yes -o csv billing.example.com

# Magento 2 forçando esquema HTTP
chgurl -m --dir /var/www/magento --scheme http --yes staging.example.com

# Atualização de configuração Joomla / Drupal
chgurl -j --dir /var/www/joomla --yes portal.example.com
chgurl -l --dir /var/www/drupal --yes drupal.example.com
```

## Exemplo de Saída Real

### Prévia Dry-Run no WordPress (`chgurl.sh --auto --dir /path/to/wp --dry-run --no-color newsite.example.com`)

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

### Execução Real no WordPress em JSON (`chgurl.sh --auto --dir /path/to/wp --yes -o json newsite.example.com`)

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

## Créditos e Licença

- **Autor Original (2012):** Percio Andrade (Percio Castelo)
- **Contribuidores Originais (2012):** Jose Terra, Leonardo Bolsoni
- **Licença:** [Apache License 2.0](LICENSE)
