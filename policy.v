module main

import net.urllib
import os

const redirect_statuses = [301, 302, 303, 307, 308]

// host_allowed reports whether host matches an entry. "*.example.com" matches
// subdomains of example.com but not example.com itself. An empty list allows
// every host.
fn host_allowed(host string, allow_hosts []string) bool {
	if allow_hosts.len == 0 {
		return true
	}
	candidate := host.to_lower().trim_right('.')
	for entry in allow_hosts {
		pattern := entry.to_lower().trim_space().trim_right('.')
		if pattern.starts_with('*.') {
			if candidate.ends_with(pattern[1..]) && candidate.len > pattern.len - 1 {
				return true
			}
		} else if candidate == pattern {
			return true
		}
	}
	return false
}

// effective_allow_hosts merges --allow-host with ARTIFACT_BRIDGE_ALLOW_HOSTS,
// a comma-separated list.
fn effective_allow_hosts(flags []string) []string {
	mut hosts := flags.clone()
	for entry in os.getenv('ARTIFACT_BRIDGE_ALLOW_HOSTS').split(',') {
		if entry.trim_space() != '' {
			hosts << entry.trim_space()
		}
	}
	return hosts
}

fn validate_allow_host(entry string) ! {
	pattern := entry.trim_space()
	bare := if pattern.starts_with('*.') { pattern[2..] } else { pattern }
	if bare == '' || bare.contains_any('*/:@ ') {
		return error('--allow-host must be a host name such as example.com or *.example.com')
	}
}

fn origin(url urllib.URL) string {
	return '${url.scheme}://${url.hostname().to_lower()}:${effective_port(url)}'
}

fn effective_port(url urllib.URL) string {
	port := url.port()
	if port != '' {
		return port
	}
	return if url.scheme == 'https' { '443' } else { '80' }
}

// check_url_policy enforces the scheme and host policy for one hop of a
// fetch, before any request is sent to it.
fn check_url_policy(url urllib.URL, options FetchOptions, allow_hosts []string, with_credentials bool) ! {
	if url.scheme !in ['http', 'https'] {
		return fail('unsupported_scheme', 'unsupported URL scheme "${url.scheme}"')
	}
	if url.hostname() == '' {
		return fail('invalid_argument', 'URL has no host')
	}
	if !host_allowed(url.hostname(), allow_hosts) {
		return fail('host_not_allowed', 'host ${url.hostname()} is not in the allowed host list')
	}
	if with_credentials && url.scheme != 'https' && !options.allow_insecure_http {
		return fail('insecure_http',
			'refusing to send --header-env credentials over plain HTTP; use HTTPS or --allow-insecure-http')
	}
}
