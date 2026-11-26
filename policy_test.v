module main

import net
import json
import os

struct TestServer {
mut:
	listener &net.TcpListener
	port     int
	log      chan string
}

fn start_server(redirect_to string) &TestServer {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { panic(err) }
	port := listener.addr() or { panic(err) }.port() or { panic(err) }
	mut server := &TestServer{
		listener: listener
		port:     port
		log:      chan string{cap: 32}
	}
	spawn serve(mut listener, server.log, redirect_to)
	return server
}

fn serve(mut listener net.TcpListener, log chan string, redirect_to string) {
	for {
		mut conn := listener.accept() or { return }
		mut buf := []u8{len: 4096}
		n := conn.read(mut buf) or { 0 }
		request := buf[..n].bytestr()
		path := request.all_after(' ').all_before(' ')
		mut auth := ''
		for line in request.split('\r\n') {
			if line.to_lower().starts_with('authorization:') {
				auth = line.all_after(':').trim_space()
			}
		}
		log <- '${path}|${auth}'
		response := match path {
			'/same' { 'HTTP/1.1 302 Found\r\nLocation: /file\r\nContent-Length: 0\r\n\r\n' }
			'/cross' { 'HTTP/1.1 302 Found\r\nLocation: ${redirect_to}\r\nContent-Length: 0\r\n\r\n' }
			'/loop' { 'HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\n\r\n' }
			else { 'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: 8\r\n\r\nartifact' }
		}

		conn.write_string(response) or {}
		conn.close() or {}
	}
}

fn drain(log chan string) []string {
	mut entries := []string{}
	for {
		select {
			entry := <-log {
				entries << entry
			}
			else {
				break
			}
		}
	}
	return entries
}

fn fetch_options_for(url string, name string) FetchOptions {
	os.setenv('AB_TEST_TOKEN', 'secret-token', true)
	return FetchOptions{
		url:                 url
		output:              os.join_path(os.temp_dir(), 'artifact-bridge-${name}-${os.getpid()}')
		header_env:          ['Authorization=AB_TEST_TOKEN']
		allow_insecure_http: true
		force:               true
		timeout_ms:          2_000
	}
}

fn test_host_allowed_matching() {
	assert host_allowed('anything.example', [])
	assert host_allowed('Artifacts.Example.com', ['artifacts.example.com'])
	assert host_allowed('a.b.example.com', ['*.example.com'])
	assert !host_allowed('example.com', ['*.example.com'])
	assert !host_allowed('evilexample.com', ['*.example.com'])
	assert !host_allowed('example.com.evil.net', ['example.com'])
}

fn test_validate_allow_host_rejects_urls_and_ports() {
	for bad in ['https://example.com', 'example.com:443', '*', '*.', 'a*.example.com'] {
		if _ := validate_allow_host(bad) {
			assert false, 'expected ${bad} to be rejected'
		}
	}
	validate_allow_host('*.example.com')!
}

fn test_same_origin_redirect_keeps_credentials() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	options := fetch_options_for('http://127.0.0.1:${server.port}/same', 'same')
	report := fetch_artifact(options)!
	os.rm(options.output) or {}
	assert report.bytes == 8
	assert report.redirects == ['http://127.0.0.1:${server.port}/file']
	assert drain(server.log) == ['/same|secret-token', '/file|secret-token']
}

fn test_cross_origin_redirect_drops_credentials() {
	mut target := start_server('')
	mut origin_server := start_server('http://127.0.0.1:${target.port}/file')
	defer {
		target.listener.close() or {}
		origin_server.listener.close() or {}
	}
	options := fetch_options_for('http://127.0.0.1:${origin_server.port}/cross', 'cross')
	fetch_artifact(options)!
	os.rm(options.output) or {}
	assert drain(origin_server.log) == ['/cross|secret-token']
	assert drain(target.log) == ['/file|']
}

fn test_disallowed_host_is_never_contacted() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	mut options := fetch_options_for('http://127.0.0.1:${server.port}/file', 'denied')
	options.allow_hosts = ['artifacts.example.com']
	if _ := fetch_artifact(options) {
		assert false, 'expected host policy error'
	} else {
		assert err.msg().contains('not in the allowed host list')
	}
	assert drain(server.log).len == 0
}

fn test_redirect_to_disallowed_host_is_blocked() {
	mut target := start_server('')
	mut origin_server := start_server('http://localhost:${target.port}/file')
	defer {
		target.listener.close() or {}
		origin_server.listener.close() or {}
	}
	mut options := fetch_options_for('http://127.0.0.1:${origin_server.port}/cross',
		'redirect-denied')
	options.allow_hosts = ['127.0.0.1']
	if _ := fetch_artifact(options) {
		assert false, 'expected host policy error'
	} else {
		assert err.msg().contains('localhost')
	}
	assert drain(target.log).len == 0
}

fn test_redirect_limit() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	mut options := fetch_options_for('http://127.0.0.1:${server.port}/loop', 'loop')
	options.max_redirects = 2
	if _ := fetch_artifact(options) {
		assert false, 'expected redirect limit error'
	} else {
		assert err.msg().contains('too many redirects')
	}
	assert drain(server.log).len == 3
}

fn test_credentials_require_https_by_default() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	mut options := fetch_options_for('http://127.0.0.1:${server.port}/file', 'insecure')
	options.allow_insecure_http = false
	if _ := fetch_artifact(options) {
		assert false, 'expected HTTPS requirement error'
	} else {
		assert err.msg().contains('plain HTTP')
	}
	assert drain(server.log).len == 0
}

fn test_env_allow_hosts_are_merged() {
	os.setenv('ARTIFACT_BRIDGE_ALLOW_HOSTS', 'a.example.com, *.b.example.com', true)
	defer {
		os.unsetenv('ARTIFACT_BRIDGE_ALLOW_HOSTS')
	}
	assert effective_allow_hosts(['c.example.com']) == ['c.example.com', 'a.example.com',
		'*.b.example.com']
}

fn failure_code(options FetchOptions) string {
	fetch_artifact(options) or {
		return failure_report(options.url, options.output, err).error.code
	}
	return 'ok'
}

fn test_failure_codes_for_validation_paths() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	base := fetch_options_for('http://127.0.0.1:${server.port}/file', 'codes')
	assert failure_code(FetchOptions{
		...base
		sha256: '0'.repeat(64)
	}) == 'digest_mismatch'
	assert failure_code(FetchOptions{
		...base
		max_bytes: 1
	}) == 'size_exceeded'
	assert failure_code(FetchOptions{
		...base
		header_env: ['Authorization=AB_TEST_UNSET']
	}) == 'credential_env_missing'
	assert failure_code(FetchOptions{
		...base
		allow_hosts: ['example.com']
	}) == 'host_not_allowed'
	os.write_file(base.output, 'x')!
	defer {
		os.rm(base.output) or {}
	}
	assert failure_code(FetchOptions{
		...base
		force: false
	}) == 'output_exists'
}

fn test_network_failure_is_retryable() {
	report := failure_report('https://example.com/a', 'a',
		error('net.dial_tcp failed: connection refused'))
	assert report.error.code == 'network'
	assert report.error.retryable
}

fn test_http_status_retryability() {
	assert is_retryable_status(429)
	assert is_retryable_status(503)
	assert !is_retryable_status(403)
	assert !is_retryable_status(404)
}

fn test_failure_report_redacts_url_and_omits_empty_fields() {
	report := failure_report('https://user:pass@example.com/build.zip?token=secret', 'build.zip', FetchFailure{
		code:        'http_status'
		message:     'unexpected HTTP status 403'
		http_status: 403
	})
	encoded := json.encode(report)
	assert !encoded.contains('secret')
	assert !encoded.contains('pass@')
	assert encoded.contains('"ok":false')
	assert encoded.contains('"http_status":403')
	assert !encoded.contains('expected_sha256')
}

fn test_digest_mismatch_reports_both_digests() {
	mut server := start_server('')
	defer {
		server.listener.close() or {}
	}
	options := FetchOptions{
		...fetch_options_for('http://127.0.0.1:${server.port}/file', 'digest')
		sha256: 'a'.repeat(64)
	}
	fetch_artifact(options) or {
		report := failure_report(options.url, options.output, err)
		assert report.error.expected_sha256 == 'a'.repeat(64)
		assert report.error.actual_sha256.len == 64
		assert !report.error.retryable
		return
	}
	assert false, 'expected digest mismatch'
}
