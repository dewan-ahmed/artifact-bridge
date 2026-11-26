module main

import crypto.sha256
import net.http
import net.urllib
import os
import time

fn fetch_artifact(options FetchOptions) !FetchReport {
	if os.exists(options.output) && !options.force {
		return fail('output_exists', 'output already exists; use --force to replace it')
	}
	parent := os.dir(options.output)
	if parent != '.' && !os.is_dir(parent) {
		return fail('output_dir_missing', 'output directory does not exist: ${parent}')
	}
	mut headers := http.Header{}
	for spec in options.header_env {
		header, env_name := parse_header_env(spec) or { return fail('invalid_argument', err.msg()) }
		value := os.getenv(env_name)
		if value == '' {
			return FetchFailure{
				code:     'credential_env_missing'
				message:  'environment variable ${env_name} is empty or unset'
				env_name: env_name
			}
		}
		headers.add_custom(header, value) or { return fail('invalid_argument', err.msg()) }
	}
	allow_hosts := effective_allow_hosts(options.allow_hosts)
	for entry in allow_hosts {
		validate_allow_host(entry) or {
			return fail('invalid_argument', 'ARTIFACT_BRIDGE_ALLOW_HOSTS: ${err.msg()}')
		}
	}
	mut current := urllib.parse(options.url) or { return fail('invalid_argument', 'invalid URL') }
	first_origin := origin(current)
	mut redirects := []string{}
	mut response := http.Response{}
	temp_path := '${options.output}.part-${os.getpid()}'
	mut sink := &StreamSink{
		path:       temp_path
		max_bytes:  options.max_bytes
		allow_html: options.allow_html
		hasher:     sha256.new()
	}
	defer {
		sink.close()
		os.rm(temp_path) or {}
	}
	for {
		// Credentials only go to the origin of the URL the caller gave.
		send_credentials := headers.keys().len > 0 && origin(current) == first_origin
		check_url_policy(current, options, allow_hosts, send_credentials)!
		response = http.fetch(
			url:                current.str()
			method:             .get
			header:             if send_credentials { headers } else { http.Header{} }
			allow_redirect:     false
			read_timeout:       i64(options.timeout_ms) * time.millisecond
			write_timeout:      i64(options.timeout_ms) * time.millisecond
			max_retries:        2
			user_ptr:           sink
			on_progress_body:   stream_chunk
			stop_copying_limit: sniff_bytes
		)!
		if response.status_code !in redirect_statuses {
			break
		}
		if redirects.len >= options.max_redirects {
			return fail('redirect_limit',
				'too many redirects; the limit is ${options.max_redirects}')
		}
		location := response.header.get(.location) or {
			return fail('redirect_invalid',
				'redirect ${response.status_code} has no Location header')
		}
		next := current.parse(location) or {
			return fail('redirect_invalid', 'redirect has an invalid Location')
		}
		if current.scheme == 'https' && next.scheme == 'http' && !options.allow_insecure_http {
			return fail('insecure_http', 'refusing redirect from HTTPS to plain HTTP')
		}
		current = next
		redirects << safe_url(current.str())
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return FetchFailure{
			code:        'http_status'
			message:     'unexpected HTTP status ${response.status_code}'
			http_status: response.status_code
			retryable:   is_retryable_status(response.status_code)
		}
	}
	content_type := response.header.get(.content_type) or { '' }
	if !options.allow_html && is_html(content_type, '') {
		return html_failure()
	}
	sink.finish()!
	digest := sink.hasher.sum([]u8{}).hex()
	if options.sha256 != '' && digest != options.sha256 {
		return FetchFailure{
			code:            'digest_mismatch'
			message:         'SHA-256 mismatch: expected ${options.sha256}, received ${digest}'
			expected_sha256: options.sha256
			actual_sha256:   digest
		}
	}
	os.mv(temp_path, options.output) or { return fail('write_failed', err.msg()) }
	return FetchReport{
		url:          safe_url(options.url)
		path:         options.output
		bytes:        sink.written
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
