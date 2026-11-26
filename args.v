module main

fn parse_fetch_args(args []string) !FetchOptions {
	if args.len == 0 {
		return error('fetch requires a URL')
	}
	mut options := FetchOptions{
		url: args[0]
	}
	mut index := 1
	for index < args.len {
		match args[index] {
			'--out', '-o' {
				options.output = option_value(args, index)!
				index += 2
			}
			'--max-bytes' {
				value := option_value(args, index)!
				options.max_bytes = value.i64()
				if options.max_bytes < 1 {
					return error('--max-bytes must be positive')
				}
				index += 2
			}
			'--sha256' {
				options.sha256 = option_value(args, index)!.to_lower()
				if !is_sha256(options.sha256) {
					return error('--sha256 must contain 64 hexadecimal characters')
				}
				index += 2
			}
			'--header-env' {
				options.header_env << option_value(args, index)!
				index += 2
			}
			'--timeout-ms' {
				value := option_value(args, index)!
				options.timeout_ms = value.int()
				if options.timeout_ms < 1 {
					return error('--timeout-ms must be positive')
				}
				index += 2
			}
			'--allow-host' {
				host := option_value(args, index)!
				validate_allow_host(host)!
				options.allow_hosts << host.trim_space()
				index += 2
			}
			'--allow-insecure-http' {
				options.allow_insecure_http = true
				index++
			}
			'--max-redirects' {
				value := option_value(args, index)!
				if value == '' || !value.bytes().all(it.is_digit()) || value.len > 3 {
					return error('--max-redirects must be a whole number')
				}
				options.max_redirects = value.int()
				index += 2
			}
			'--allow-html' {
				options.allow_html = true
				index++
			}
			'--force' {
				options.force = true
				index++
			}
			'--json' {
				options.json = true
				index++
			}
			else {
				return error('unknown option "${args[index]}"')
			}
		}
	}
	if options.output == '' {
		return error('fetch requires --out')
	}
	return options
}

fn is_sha256(value string) bool {
	if value.len != 64 {
		return false
	}
	for character in value.bytes() {
		if !character.is_hex_digit() {
			return false
		}
	}
	return true
}

fn option_value(args []string, index int) !string {
	if index + 1 >= args.len {
		return error('${args[index]} requires a value')
	}
	return args[index + 1]
}

fn parse_header_env(spec string) !(string, string) {
	separator := spec.index('=') or { return error('--header-env must use HEADER=ENV_VAR') }
	header := spec[..separator].trim_space()
	env_name := spec[separator + 1..].trim_space()
	if header == '' || env_name == '' {
		return error('--header-env must use HEADER=ENV_VAR')
	}
	return header, env_name
}
