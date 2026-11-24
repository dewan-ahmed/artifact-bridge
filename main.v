module main

import json
import os

fn main() {
	if os.args.len < 2 || os.args[1] in ['help', '--help', '-h'] {
		print_help()
		return
	}
	if os.args[1] != 'fetch' {
		eprintln('unknown command "${os.args[1]}"')
		print_help()
		exit(2)
	}
	options := parse_fetch_args(os.args[2..]) or {
		eprintln('artifact-bridge: ${err}')
		exit(2)
	}
	report := fetch_artifact(options) or {
		eprintln('artifact-bridge: ${err}')
		exit(1)
	}
	if options.json {
		println(json.encode(report))
	} else {
		println('saved ${report.bytes} bytes to ${report.path}')
		println('sha256 ${report.sha256}')
	}
}

fn print_help() {
	println('artifact-bridge retrieves files safely for software factory workflows.')
	println('')
	println('Usage:')
	println('  artifact-bridge fetch URL --out PATH [options]')
	println('')
	println('Options:')
	println('  --max-bytes N          Reject larger responses')
	println('  --sha256 HASH          Require an expected SHA-256 digest')
	println('  --header-env H=ENV     Read an HTTP header value from an environment variable')
	println('  --timeout-ms N         Set the request timeout')
	println('  --allow-html           Permit HTML responses')
	println('  --force                Replace an existing output file')
	println('  --json                 Emit a machine-readable report')
}
