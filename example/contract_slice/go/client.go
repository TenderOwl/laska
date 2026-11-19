// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Regenerate with: laska contract sdk --lang=go

package users

import (
	"errors"
	"fmt"
	"time"

	"github.com/TenderOwl/laska/example/contract_slice/go/internal/grpc"
)

// The codes of the status of a call, as gRPC defines them.
const (
	// StatusOK is the status of a call that succeeded.
	StatusOK = 0
	// StatusInvalidArgument is the status of a call that was malformed.
	StatusInvalidArgument = 3
	// StatusDeadlineExceeded is the status of a call that ran out of time.
	StatusDeadlineExceeded = 4
	// StatusNotFound is the status of a call that asked for something that is not there.
	StatusNotFound = 5
	// StatusInternal is the status of a call that failed inside the service.
	StatusInternal = 13
	// StatusUnavailable is the status of a call that could not reach the service.
	StatusUnavailable = 14
)

// CallOptions holds the options of a call to a service.
type CallOptions struct {
	// Timeout of the call. The timeout of the client is used when it is zero.
	Timeout time.Duration
	// Metadata is sent with the call.
	Metadata map[string]string
}

// StatusError is the failure of a call to a service.
type StatusError struct {
	// Code of the status, as gRPC defines it.
	Code int
	// Message of the status.
	Message string
}

// Error returns the message of the failure.
func (e *StatusError) Error() string {
	return fmt.Sprintf("the call failed with the status %d: %s", e.Code, e.Message)
}

// statusErrorOf turns the failure of the transport into the failure of the
// service, so a caller may read the status of the call.
func statusErrorOf(err error) error {
	var status *grpc.Status
	if errors.As(err, &status) {
		return &StatusError{Code: status.Code, Message: status.Message}
	}
	return err
}
