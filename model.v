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
}

struct FetchReport {
	url          string
	path         string
	bytes        int
	sha256       string
	content_type string
	http_status  int
}
