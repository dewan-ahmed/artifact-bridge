module main

import crypto.sha256
import net.http
import net.urllib
import os
import time

fn fetch_artifact(options FetchOptions) !FetchReport {
	if os.exists(options.output) && !options.force {
		return error('output already exists; use --force to replace it')
	}
	parent := os.dir(options.output)
	if parent != '.' && !os.is_dir(parent) {
		return error('output directory does not exist: ${parent}')
	}
	mut headers := http.Header{}
	for spec in options.header_env {
		header, env_name := parse_header_env(spec)!
		value := os.getenv(env_name)
		if value == '' {
			return error('environment variable ${env_name} is empty or unset')
		}
		headers.add_custom(header, value)!
	}
	allow_hosts := effective_allow_hosts(options.allow_hosts)
	for entry in allow_hosts {
		validate_allow_host(entry) or { return error('ARTIFACT_BRIDGE_ALLOW_HOSTS: ${err.msg()}') }
	}
	mut current := urllib.parse(options.url) or { return error('invalid URL') }
	first_origin := origin(current)
	mut redirects := []string{}
	mut response := http.Response{}
	for {
		// Credentials only go to the origin of the URL the caller gave.
		send_credentials := headers.keys().len > 0 && origin(current) == first_origin
		check_url_policy(current, options, allow_hosts, send_credentials)!
		response = http.fetch(
			url:                  current.str()
			method:               .get
			header:               if send_credentials { headers } else { http.Header{} }
			allow_redirect:       false
			read_timeout:         i64(options.timeout_ms) * time.millisecond
			write_timeout:        i64(options.timeout_ms) * time.millisecond
			max_retries:          2
			stop_receiving_limit: options.max_bytes + 1
		)!
		if response.status_code !in redirect_statuses {
			break
		}
		if redirects.len >= options.max_redirects {
			return error('too many redirects; the limit is ${options.max_redirects}')
		}
		location := response.header.get(.location) or {
			return error('redirect ${response.status_code} has no Location header')
		}
		next := current.parse(location) or { return error('redirect has an invalid Location') }
		if current.scheme == 'https' && next.scheme == 'http' && !options.allow_insecure_http {
			return error('refusing redirect from HTTPS to plain HTTP')
		}
		current = next
		redirects << safe_url(current.str())
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('unexpected HTTP status ${response.status_code}')
	}
	content_type := response.header.get(.content_type) or { '' }
	if !options.allow_html && is_html(content_type, response.body) {
		return error('refusing HTML response; this usually indicates a login page or API error')
	}
	data := response.body.bytes()
	if i64(data.len) > options.max_bytes {
		return error('artifact exceeds maximum size of ${options.max_bytes} bytes')
	}
	digest := sha256.sum(data).hex()
	if options.sha256 != '' && digest != options.sha256 {
		return error('SHA-256 mismatch: expected ${options.sha256}, received ${digest}')
	}
	temp_path := '${options.output}.part-${os.getpid()}'
	os.write_file_array(temp_path, data)!
	os.mv(temp_path, options.output) or {
		os.rm(temp_path) or {}
		return err
	}
	return FetchReport{
		url:          safe_url(options.url)
		path:         options.output
		bytes:        data.len
		sha256:       digest
		content_type: content_type
		http_status:  response.status_code
		redirects:    redirects
	}
}

fn is_html(content_type string, body string) bool {
	if content_type.to_lower().contains('text/html') {
		return true
	}
	prefix := body.trim_space().to_lower()
	return prefix.starts_with('<!doctype html') || prefix.starts_with('<html')
}

fn safe_url(url string) string {
	mut clean := url.all_before('?')
	if scheme_index := clean.index('://') {
		prefix := clean[..scheme_index + 3]
		remainder := clean[scheme_index + 3..]
		host_end := remainder.index('/') or { remainder.len }
		authority := remainder[..host_end]
		if at_index := authority.last_index('@') {
			clean = prefix + authority[at_index + 1..] + remainder[host_end..]
		}
	}
	return clean
}
