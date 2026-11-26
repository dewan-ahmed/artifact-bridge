module main

struct FetchOptions {
	url string
mut:
	output     string
	max_bytes  i64 = 100 * 1024 * 1024
	sha256     string
	header_env []string
	allow_html bool
	force      bool
	json       bool
	timeout_ms int = 30_000
	// allow_hosts restricts the initial URL and every redirect target.
	allow_hosts         []string
	allow_insecure_http bool
	max_redirects       int = 5
}

struct FetchReport {
	ok           bool = true
	url          string
	path         string
	bytes        i64
	sha256       string
	content_type string
	http_status  int
	redirects    []string
}
