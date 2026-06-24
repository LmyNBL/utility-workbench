#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

def abort_usage
  abort <<~USAGE
    usage: ruby apply-profile-overlay.rb GROUPS_YML INPUT_CLASH_YAML OUTPUT_CLASH_YAML

    Required environment variables by default:
      DIALER_SERVER    e.g. 192.168.50.41
      DIALER_PORT      e.g. 7891

    Optional environment variables:
      DIALER_USERNAME
      DIALER_PASSWORD
      DIALER_NAME
      DIALER_TYPE
      DIALER_SUFFIX
  USAGE
end

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def env_or_config(env_name, config_value, required: false)
  value = ENV[env_name.to_s]
  value = config_value if value.nil? || value.empty?
  if required && (value.nil? || value.to_s.empty?)
    abort "missing required value: #{env_name}"
  end
  value
end

groups_path, input_path, output_path = ARGV
abort_usage unless groups_path && input_path && output_path

manifest = YAML.load_file(groups_path)
config = YAML.load_file(input_path)

overlay = manifest.fetch("overlay", {})
suffix = env_or_config("DIALER_SUFFIX", overlay["suffix"] || "-dialer-proxy")
dialer_name = env_or_config("DIALER_NAME", overlay["dialer_name"] || "VPS-Dialer")
dialer_type = env_or_config("DIALER_TYPE", overlay["dialer_type"] || "socks5")
server = env_or_config(overlay["dialer_server_env"] || "DIALER_SERVER", overlay["dialer_server"], required: true)
port = Integer(env_or_config(overlay["dialer_port_env"] || "DIALER_PORT", overlay["dialer_port"], required: true))
username = env_or_config(overlay["dialer_username_env"] || "DIALER_USERNAME", overlay["dialer_username"])
password = env_or_config(overlay["dialer_password_env"] || "DIALER_PASSWORD", overlay["dialer_password"])
udp = overlay.key?("dialer_udp") ? overlay["dialer_udp"] : true
append_to_parent_groups = overlay.key?("append_to_parent_groups") ? overlay["append_to_parent_groups"] : true
target_groups = manifest.fetch("target_groups")

proxies = config["proxies"] ||= []
groups = config["proxy-groups"] ||= []

proxy_name_counts = Hash.new(0)
proxies.each { |proxy| proxy_name_counts[proxy["name"]] += 1 if proxy["name"] }
duplicates = proxy_name_counts.select { |_name, count| count > 1 }
abort "duplicate proxy names in input: #{duplicates.keys.first(10).join(', ')}" unless duplicates.empty?

proxy_by_name = proxies.each_with_object({}) { |proxy, memo| memo[proxy["name"]] = proxy if proxy["name"] }
group_by_name = groups.each_with_object({}) { |group, memo| memo[group["name"]] = group if group["name"] }

dialer_proxy = {
  "name" => dialer_name,
  "type" => dialer_type,
  "server" => server,
  "port" => port,
  "udp" => udp
}
if username && !username.empty?
  dialer_proxy["username"] = username
  dialer_proxy["password"] = password.to_s
end

existing_dialer = proxy_by_name[dialer_name]
if existing_dialer
  existing_dialer.replace(dialer_proxy)
else
  proxies.unshift(dialer_proxy)
  proxy_by_name[dialer_name] = dialer_proxy
end

created_group_names = []

target_groups.each do |group_name|
  group = group_by_name[group_name]
  abort "target group not found: #{group_name}" unless group

  members = group["proxies"] || []
  cloned_members = members.map do |member_name|
    original_proxy = proxy_by_name[member_name]
    if original_proxy
      cloned_name = "#{member_name}#{suffix}"
      unless proxy_by_name[cloned_name]
        cloned_proxy = deep_copy(original_proxy)
        cloned_proxy["name"] = cloned_name
        cloned_proxy["dialer-proxy"] = dialer_name
        proxies << cloned_proxy
        proxy_by_name[cloned_name] = cloned_proxy
      end
      cloned_name
    else
      # Keep built-ins such as DIRECT/REJECT or unexpected group references intact.
      member_name
    end
  end

  cloned_group_name = "#{group_name}#{suffix}"
  cloned_group = deep_copy(group)
  cloned_group["name"] = cloned_group_name
  cloned_group["proxies"] = cloned_members

  if group_by_name[cloned_group_name]
    group_by_name[cloned_group_name].replace(cloned_group)
  else
    original_index = groups.index(group) || groups.length - 1
    groups.insert(original_index + 1, cloned_group)
    group_by_name[cloned_group_name] = cloned_group
  end
  created_group_names << cloned_group_name
end

if append_to_parent_groups
  target_groups.each do |group_name|
    cloned_group_name = "#{group_name}#{suffix}"
    groups.each do |group|
      members = group["proxies"]
      next unless members.is_a?(Array)
      next if group["name"] == cloned_group_name
      next unless members.include?(group_name)
      next if members.include?(cloned_group_name)

      index = members.index(group_name)
      members.insert(index + 1, cloned_group_name)
    end
  end
end

File.open(output_path, "w") { |file| YAML.dump(config, file) }

warn "dialer=#{dialer_name}"
warn "created_or_updated_groups=#{created_group_names.join(', ')}"
warn "output=#{output_path}"
