{% from "logstash/map.jinja" import logstash with context %}

{% set os_family = grains['os_family'] %}
{% set conf_list = salt['pillar.get']('lumberjack:extra_configs', []) %}
{% set lumberjack_port = salt['pillar.get']('logstash-forwarder:port', 7000) %}
{% set logstash_servers = [] %}
{% for id, ip_addrs in salt['mine.get']('roles:logstash', 'network.ip_addrs', expr_form='grain').items() %}
  {% do logstash_servers.append("{0}:{1}".format(ip_addrs[0], lumberjack_port)) %}
{% endfor %}
{% set conf_list = salt['pillar.get']('logstash-forwarder:extra_configs', []) %}
{% set logstash_timeout = salt['pillar.get']('logstash-forwarder:logstash_timeout', 15) %}
{% set use_public_pkg_repo = salt['pillar.get']('logstash-forwarder:use_public_pkg_repo', True) %}

{% if use_public_pkg_repo == True %}
setup_lumberjack_pkg_repo:
  pkgrepo.managed:
    - humanname: Logstash
    {% if os_family == 'Debian' %}
    - name: deb http://packages.elasticsearch.org/logstashforwarder/debian stable main
    {% elif os_family == 'RedHat' %}
    - baseurl: http://packages.elasticsearch.org/logstashforwarder/centos
    - gpgcheck: 1
    - enabled: 1
    {% endif %}
    - key_url: http://packages.elasticsearch.org/GPG-KEY-elasticsearch
    - require_in:
        - pkg: logstash-forwarder
{% endif %}

logstash-forwarder_pkg :
  pkg.installed:
    {% if use_public_pkg_repo %}
    - name: logstash-forwarder
    {% else %}
    {% if os_family == 'Debian' %}
        {% set package_type = 'deb' %}
    {% elif os_family == 'RedHat' %}
        {% set package_type = 'rpm' %}
    {% endif %}
    - sources:
        - logstash-forwarder: salt://built_packages/logstash-forwarder.{{ package_type }}
    {% endif %}

lumberjack_config_dir:
  file.directory:
    - name: /etc/logstash-forwarder/
    - makedirs: True

lumberjack_ssl_key:
  file.managed:
    - name: /etc/logstash-forwarder-ssl/logstash-forwarder.key
    - contents_pillar: logstash-forwarder:ssl_key
    - makedirs: True

lumberjack_ssl_cert:
  file.managed:
    - name: /etc/logstash-forwarder-ssl/logstash-forwarder.crt
    - contents_pillar: logstash-forwarder:ssl_cert
    - makedirs: True

base_config:
  file.managed:
    - name: /etc/logstash-forwarder/logstash_connection.conf
    - source: salt://logstash/files/lumberjack.conf
    - template: jinja
    - context:
        logstash_servers: {{ logstash_servers }}
        logstash_timeout: {{ logstash_timeout }}
    - require:
        - file: lumberjack_config_dir

{% for config in conf_list %}
{{ config.name }}:
  file.managed:
    - name: /etc/logstash-forwarder/{{ config.name }}.conf
    - source: {{ config.source }}
    {% if config.get('source_hash') %}
    - source_hash: {{ config.source_hash }}
    {% endif %}
    - watch_in:
        - service: forwarder_service
{% endfor %}

forwarder_service:
  service.running:
    - name: logstash-forwarder
    - enable: True
    - require:
        - pkg: logstash-forwarder_pkg
    - watch:
        - file: lumberjack_config_dir
        - file: base_config