module main

fn test_parse_header_env() {
	header, env_name := parse_header_env('Authorization=FACTORY_TOKEN') or {
		assert false, err.msg()
		return
	}
	assert header == 'Authorization'
	assert env_name == 'FACTORY_TOKEN'
}

fn test_parse_fetch_args_requires_output() {
	parse_fetch_args(['https://example.com/file']) or {
		assert err.msg().contains('--out')
		return
	}
	assert false, 'expected argument error'
}

fn test_parse_fetch_args_rejects_non_hex_sha256() {
	parse_fetch_args([
		'https://example.com/file',
		'--out',
		'file',
		'--sha256',
		'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
	]) or {
		assert err.msg().contains('hexadecimal')
		return
	}
	assert false, 'expected checksum argument error'
}

fn test_safe_url_removes_credentials_and_query() {
	url := safe_url('https://user:secret@example.com/file.zip?token=secret')
	assert url == 'https://example.com/file.zip'
}

fn test_is_html_detects_header_and_body() {
	assert is_html('text/html; charset=utf-8', 'content')
	assert is_html('application/octet-stream', '<!doctype html><title>Login</title>')
	assert !is_html('application/zip', 'PK')
}
