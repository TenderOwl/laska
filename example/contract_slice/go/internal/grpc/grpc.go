// Package grpc talks to a gRPC server over HTTP/2.
//
// The transport of the package is the one of the protocol buffers: the body of
// a call is a framed message, and the status of the call is a pair of the
// headers of the answer. A service of Laska is reached over HTTP/2 without
// encryption, the way a service of a cluster is reached.
package grpc

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// The status codes of the protocol buffers.
const (
	// CodeOK is the status of a call that succeeded.
	CodeOK = 0
)

// Status is the status of a call that did not succeed.
type Status struct {
	// Code of the status, as the protocol buffers define it.
	Code int
	// Message of the status.
	Message string
}

// Error returns the message of the status.
func (s *Status) Error() string {
	return fmt.Sprintf("grpc: the call failed with the status %d: %s", s.Code, s.Message)
}

// Conn is a connection to a gRPC server.
type Conn struct {
	baseURL string
	client  *http.Client
	timeout time.Duration
}

// Dial opens a connection to the server at [target].
//
// The target is a host and a port, e.g. `localhost:50051`, or a URL. A target
// that starts with `https` is reached over TLS, every other target is reached
// over HTTP/2 without encryption.
//
// The [timeout] is the timeout of a call that has no deadline of its own.
func Dial(target string, timeout time.Duration) (*Conn, error) {
	baseURL, secure, err := parseTarget(target)
	if err != nil {
		return nil, err
	}

	protocols := new(http.Protocols)
	transport := &http.Transport{
		Protocols: protocols,
		DialContext: (&net.Dialer{
			Timeout:   10 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
	}
	if secure {
		protocols.SetHTTP2(true)
		transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	} else {
		protocols.SetUnencryptedHTTP2(true)
	}

	return &Conn{
		baseURL: baseURL,
		client:  &http.Client{Transport: transport},
		timeout: timeout,
	}, nil
}

// Close closes the connection.
func (c *Conn) Close() error {
	c.client.CloseIdleConnections()
	return nil
}

// Invoke calls the method [method] of the server and returns the bytes of the
// answer.
//
// The method is the path of the call, e.g. `/users.v1.UsersService/GetUser`.
func (c *Conn) Invoke(
	ctx context.Context,
	method string,
	request []byte,
	metadata map[string]string,
) ([]byte, error) {
	if c.timeout > 0 {
		if _, ok := ctx.Deadline(); !ok {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, c.timeout)
			defer cancel()
		}
	}

	body := make([]byte, 5+len(request))
	binary.BigEndian.PutUint32(body[1:5], uint32(len(request)))
	copy(body[5:], request)

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		c.baseURL+method,
		bytes.NewReader(body),
	)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/grpc+proto")
	req.Header.Set("User-Agent", "laska-go-sdk")
	for key, value := range metadata {
		req.Header.Set(key, value)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf(
			"grpc: the server answered with the HTTP status %d",
			resp.StatusCode,
		)
	}

	code, message, found := statusOf(resp)
	if !found {
		return nil, errors.New("grpc: the answer of the server carries no status")
	}
	if code != CodeOK {
		return nil, &Status{Code: code, Message: message}
	}

	return unframe(data)
}

// parseTarget reads the target of a server.
func parseTarget(target string) (baseURL string, secure bool, err error) {
	if target == "" {
		return "", false, errors.New("grpc: the target of the server is empty")
	}
	if !strings.Contains(target, "://") {
		target = "http://" + target
	}

	parsed, err := url.Parse(target)
	if err != nil {
		return "", false, fmt.Errorf("grpc: the target %q is not a URL: %w", target, err)
	}
	if parsed.Host == "" {
		return "", false, fmt.Errorf("grpc: the target %q has no host", target)
	}
	if parsed.Port() == "" {
		if parsed.Scheme == "https" {
			parsed.Host = net.JoinHostPort(parsed.Host, "443")
		} else {
			parsed.Host = net.JoinHostPort(parsed.Host, "80")
		}
	}

	return strings.TrimSuffix(parsed.String(), "/"), parsed.Scheme == "https", nil
}

// statusOf reads the status of a call out of the answer of the server.
//
// The status is in the trailers of the answer, or in its headers when the
// answer carries nothing but the status.
func statusOf(resp *http.Response) (code int, message string, found bool) {
	value := resp.Header.Get("Grpc-Status")
	if value == "" {
		value = resp.Trailer.Get("Grpc-Status")
	}
	if value == "" {
		return 0, "", false
	}

	number, err := strconv.Atoi(value)
	if err != nil {
		return 0, "", false
	}

	text := resp.Trailer.Get("Grpc-Message")
	if text == "" {
		text = resp.Header.Get("Grpc-Message")
	}
	if decoded, err := url.PathUnescape(text); err == nil {
		text = decoded
	}

	return number, text, true
}

// unframe reads the message out of the frames of the answer.
func unframe(data []byte) ([]byte, error) {
	if len(data) == 0 {
		return nil, nil
	}
	if len(data) < 5 {
		return nil, errors.New("grpc: the answer of the server is not a framed message")
	}
	if data[0] != 0 {
		return nil, errors.New("grpc: the answer of the server is compressed")
	}

	size := binary.BigEndian.Uint32(data[1:5])
	if uint64(len(data)-5) < uint64(size) {
		return nil, errors.New("grpc: the frame of the answer is cut short")
	}

	return data[5 : 5+size], nil
}
