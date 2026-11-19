// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Regenerate with: laska contract sdk --lang=go

package users

import "time"

// CallOptions holds the options of a call to a service.
type CallOptions struct {
	// Timeout of the call. The timeout of the client is used when it is zero.
	Timeout time.Duration
	// Metadata is sent with the call.
	Metadata map[string]string
}
