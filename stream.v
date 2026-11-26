module main

import hash
import net.http
import os

// Bytes of each response kept in memory; the artifact body goes to disk.
const sniff_bytes = 64 * 1024

@[heap]
struct StreamSink {
	path       string
	max_bytes  i64
	allow_html bool
mut:
	file    os.File
	opened  bool
	hasher  hash.Hash
	written i64
}

// stream_chunk writes each 200 body chunk to the temporary file and hashes it,
// so memory use stays flat regardless of artifact size. Returning an error
// aborts the transfer.
fn stream_chunk(request &http.Request, chunk []u8, body_so_far u64, expected u64, status int) ! {
	if status != 200 || chunk.len == 0 {
		return
	}
	mut sink := unsafe { &StreamSink(request.user_ptr) }
	if body_so_far == u64(chunk.len) {
		// First chunk of a response, including a retried one: start over.
		sink.start()!
		if expected > 0 && i64(expected) > sink.max_bytes {
			return sink.size_failure()
		}
		if !sink.allow_html && is_html('', chunk.bytestr()) {
			return html_failure()
		}
	}
	sink.written += chunk.len
	if sink.written > sink.max_bytes {
		return sink.size_failure()
	}
	sink.file.write(chunk) or { return fail('write_failed', err.msg()) }
	sink.hasher.write(chunk) or { return fail('write_failed', err.msg()) }
}

fn (mut sink StreamSink) start() ! {
	sink.close()
	sink.file = os.create(sink.path) or { return fail('write_failed', err.msg()) }
	sink.opened = true
	sink.hasher.reset()
	sink.written = 0
}

// finish flushes the file; an empty 200 body still produces an empty file.
fn (mut sink StreamSink) finish() ! {
	if !sink.opened {
		sink.start()!
	}
	sink.close()
}

fn (mut sink StreamSink) close() {
	if sink.opened {
		sink.file.close()
		sink.opened = false
	}
}

fn (sink &StreamSink) size_failure() IError {
	return FetchFailure{
		code:      'size_exceeded'
		message:   'artifact exceeds maximum size of ${sink.max_bytes} bytes'
		max_bytes: sink.max_bytes
	}
}

fn html_failure() IError {
	return fail('html_response',
		'refusing HTML response; this usually indicates a login page or API error')
}
