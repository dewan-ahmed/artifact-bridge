module main

// FetchFailure is an error with a stable code, so callers can branch on the
// code instead of parsing the message.
struct FetchFailure {
	Error
	code            string
	message         string
	http_status     int
	retryable       bool
	max_bytes       i64
	expected_sha256 string
	actual_sha256   string
	env_name        string
}

fn (f FetchFailure) msg() string {
	return f.message
}

fn fail(code string, message string) IError {
	return FetchFailure{
		code:    code
		message: message
	}
}

struct ErrorDetail {
	code            string
	message         string
	retryable       bool
	http_status     int    @[omitempty]
	max_bytes       i64    @[omitempty]
	expected_sha256 string @[omitempty]
	actual_sha256   string @[omitempty]
	env_name        string @[omitempty]
}

struct FailureReport {
	ok    bool
	url   string
	path  string
	error ErrorDetail
}

// failure_report converts any error into the JSON failure contract. Errors
// from the network layer have no code and are classified here.
fn failure_report(url string, path string, err IError) FailureReport {
	detail := if err is FetchFailure {
		ErrorDetail{
			code:            err.code
			message:         err.message
			retryable:       err.retryable
			http_status:     err.http_status
			max_bytes:       err.max_bytes
			expected_sha256: err.expected_sha256
			actual_sha256:   err.actual_sha256
			env_name:        err.env_name
		}
	} else {
		message := err.msg()
		lower := message.to_lower()
		code := if lower.contains('timed out') || lower.contains('timeout') {
			'timeout'
		} else if lower.contains('certificate') || lower.contains('mbedtls')
			|| lower.contains('ssl') {
			'tls'
		} else {
			'network'
		}
		ErrorDetail{
			code:      code
			message:   message
			retryable: code in ['timeout', 'network']
		}
	}
	return FailureReport{
		url:   safe_url(url)
		path:  path
		error: detail
	}
}

fn is_retryable_status(status int) bool {
	return status == 429 || status >= 500
}
