/// The sources of the runtime of the Go SDK.
///
/// The SDK of a contract holds the runtime it needs, so a service written in
/// Go depends on nothing but the standard library of the language. The
/// sources are written here as they are, so the runtime of every SDK is the
/// same and a change of the runtime reaches every SDK at once.
library;

/// The source of the codec of the wire of the protocol buffers.
const String goWireSource =
    r'''// Package wire reads and writes the messages of a contract on the wire.
//
// The format is the one of the protocol buffers: a message is a sequence of
// fields, and every field is a tag followed by its value. The tag holds the
// number of the field and the type of its value.
package wire

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
)

// The types of the values of the wire of the protocol buffers.
const (
	// TypeVarint is a value that is written as a variable length number.
	TypeVarint = 0
	// TypeFixed64 is a value that is written as eight bytes.
	TypeFixed64 = 1
	// TypeBytes is a value that is written as a length and bytes.
	TypeBytes = 2
	// TypeFixed32 is a value that is written as four bytes.
	TypeFixed32 = 5
)

// ErrUnexpectedEnd is returned when the bytes of a message end in the middle
// of a value.
var ErrUnexpectedEnd = errors.New("wire: the message ends in the middle of a value")

// Marshaler is a message that can be written on the wire.
type Marshaler interface {
	// MarshalProto returns the bytes of the message.
	MarshalProto() []byte
}

// Unmarshaler is a message that can be read from the wire.
type Unmarshaler interface {
	// UnmarshalProto reads the message out of its bytes.
	UnmarshalProto(data []byte) error
}

// Writer writes the fields of a message on the wire.
type Writer struct {
	buf []byte
}

// NewWriter creates a writer of an empty message.
func NewWriter() *Writer {
	return &Writer{}
}

// Bytes returns the bytes written so far.
func (w *Writer) Bytes() []byte {
	return w.buf
}

// WriteTag writes the tag of a field.
func (w *Writer) WriteTag(field int, typ int) {
	w.writeVarint(uint64(field)<<3 | uint64(typ))
}

// WriteRawVarint writes a number as a variable length number, without a tag.
//
// A packed field holds the values of a field one after the other, and every
// value is written without a tag of its own.
func (w *Writer) WriteRawVarint(value uint64) {
	w.writeVarint(value)
}

// WriteRawSint32 writes a signed number of 32 bits in its zigzag form,
// without a tag.
func (w *Writer) WriteRawSint32(value int32) {
	w.writeVarint(uint64(uint32(value<<1) ^ uint32(value>>31)))
}

// WriteRawSint64 writes a signed number of 64 bits in its zigzag form,
// without a tag.
func (w *Writer) WriteRawSint64(value int64) {
	w.writeVarint(uint64(value<<1) ^ uint64(value>>63))
}

// WriteRawFixed32 writes four bytes, without a tag.
func (w *Writer) WriteRawFixed32(value uint32) {
	var buf [4]byte
	binary.LittleEndian.PutUint32(buf[:], value)
	w.buf = append(w.buf, buf[:]...)
}

// WriteRawFixed64 writes eight bytes, without a tag.
func (w *Writer) WriteRawFixed64(value uint64) {
	var buf [8]byte
	binary.LittleEndian.PutUint64(buf[:], value)
	w.buf = append(w.buf, buf[:]...)
}

// WriteRawFloat writes a number of 32 bits, without a tag.
func (w *Writer) WriteRawFloat(value float32) {
	w.WriteRawFixed32(math.Float32bits(value))
}

// WriteRawDouble writes a number of 64 bits, without a tag.
func (w *Writer) WriteRawDouble(value float64) {
	w.WriteRawFixed64(math.Float64bits(value))
}

// WriteString writes a string.
func (w *Writer) WriteString(field int, value string) {
	w.WriteBytes(field, []byte(value))
}

// WriteBytes writes bytes.
func (w *Writer) WriteBytes(field int, value []byte) {
	w.WriteTag(field, TypeBytes)
	w.writeVarint(uint64(len(value)))
	w.buf = append(w.buf, value...)
}

// WriteMessage writes a message.
func (w *Writer) WriteMessage(field int, value Marshaler) {
	w.WriteBytes(field, value.MarshalProto())
}

// WriteBool writes a boolean.
func (w *Writer) WriteBool(field int, value bool) {
	w.WriteTag(field, TypeVarint)
	if value {
		w.writeVarint(1)
	} else {
		w.writeVarint(0)
	}
}

// WriteInt32 writes a signed number of 32 bits.
func (w *Writer) WriteInt32(field int, value int32) {
	w.WriteTag(field, TypeVarint)
	w.writeVarint(uint64(int64(value)))
}

// WriteInt64 writes a signed number of 64 bits.
func (w *Writer) WriteInt64(field int, value int64) {
	w.WriteTag(field, TypeVarint)
	w.writeVarint(uint64(value))
}

// WriteUint32 writes a number of 32 bits.
func (w *Writer) WriteUint32(field int, value uint32) {
	w.WriteTag(field, TypeVarint)
	w.writeVarint(uint64(value))
}

// WriteUint64 writes a number of 64 bits.
func (w *Writer) WriteUint64(field int, value uint64) {
	w.WriteTag(field, TypeVarint)
	w.writeVarint(value)
}

// WriteEnum writes the number of an enum.
func (w *Writer) WriteEnum(field int, value int32) {
	w.WriteInt32(field, value)
}

// WriteSint32 writes a signed number of 32 bits in its zigzag form.
func (w *Writer) WriteSint32(field int, value int32) {
	w.WriteTag(field, TypeVarint)
	w.WriteRawSint32(value)
}

// WriteSint64 writes a signed number of 64 bits in its zigzag form.
func (w *Writer) WriteSint64(field int, value int64) {
	w.WriteTag(field, TypeVarint)
	w.WriteRawSint64(value)
}

// WriteFixed32 writes four bytes.
func (w *Writer) WriteFixed32(field int, value uint32) {
	w.WriteTag(field, TypeFixed32)
	w.WriteRawFixed32(value)
}

// WriteFixed64 writes eight bytes.
func (w *Writer) WriteFixed64(field int, value uint64) {
	w.WriteTag(field, TypeFixed64)
	w.WriteRawFixed64(value)
}

// WriteFloat writes a number of 32 bits.
func (w *Writer) WriteFloat(field int, value float32) {
	w.WriteFixed32(field, math.Float32bits(value))
}

// WriteDouble writes a number of 64 bits.
func (w *Writer) WriteDouble(field int, value float64) {
	w.WriteFixed64(field, math.Float64bits(value))
}

func (w *Writer) writeVarint(value uint64) {
	for value >= 0x80 {
		w.buf = append(w.buf, byte(value)|0x80)
		value >>= 7
	}
	w.buf = append(w.buf, byte(value))
}

// Reader reads the fields of a message off the wire.
type Reader struct {
	buf []byte
	pos int
}

// NewReader creates a reader over the bytes of a message.
func NewReader(data []byte) *Reader {
	return &Reader{buf: data}
}

// Done tells whether every field of the message has been read.
func (r *Reader) Done() bool {
	return r.pos >= len(r.buf)
}

// Next reads the tag of the next field.
//
// It returns io.EOF when the message is over.
func (r *Reader) Next() (field int, typ int, err error) {
	if r.Done() {
		return 0, 0, io.EOF
	}
	tag, err := r.ReadVarint()
	if err != nil {
		return 0, 0, err
	}
	field = int(tag >> 3)
	typ = int(tag & 7)
	if field == 0 {
		return 0, 0, errors.New("wire: the number 0 is not a field")
	}
	return field, typ, nil
}

// ReadVarint reads a variable length number.
func (r *Reader) ReadVarint() (uint64, error) {
	var value uint64
	var shift uint
	for {
		if r.pos >= len(r.buf) {
			return 0, ErrUnexpectedEnd
		}
		b := r.buf[r.pos]
		r.pos++
		value |= uint64(b&0x7f) << shift
		if b < 0x80 {
			return value, nil
		}
		shift += 7
		if shift > 63 {
			return 0, errors.New("wire: the number is too long")
		}
	}
}

// ReadBytes reads the bytes of a length delimited value.
func (r *Reader) ReadBytes() ([]byte, error) {
	size, err := r.ReadVarint()
	if err != nil {
		return nil, err
	}
	if uint64(len(r.buf)-r.pos) < size {
		return nil, ErrUnexpectedEnd
	}
	value := r.buf[r.pos : r.pos+int(size)]
	r.pos += int(size)
	return value, nil
}

// ReadString reads a length delimited value as a string.
func (r *Reader) ReadString() (string, error) {
	value, err := r.ReadBytes()
	if err != nil {
		return "", err
	}
	return string(value), nil
}

// ReadBool reads a boolean.
func (r *Reader) ReadBool() (bool, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return false, err
	}
	return value != 0, nil
}

// ReadInt32 reads a signed number of 32 bits.
func (r *Reader) ReadInt32() (int32, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return int32(value), nil
}

// ReadInt64 reads a signed number of 64 bits.
func (r *Reader) ReadInt64() (int64, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return int64(value), nil
}

// ReadUint32 reads a number of 32 bits.
func (r *Reader) ReadUint32() (uint32, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return uint32(value), nil
}

// ReadUint64 reads a number of 64 bits.
func (r *Reader) ReadUint64() (uint64, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return value, nil
}

// ReadEnum reads the number of an enum.
func (r *Reader) ReadEnum() (int32, error) {
	return r.ReadInt32()
}

// ReadSint32 reads a signed number of 32 bits in its zigzag form.
func (r *Reader) ReadSint32() (int32, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return int32(value>>1) ^ -int32(value&1), nil
}

// ReadSint64 reads a signed number of 64 bits in its zigzag form.
func (r *Reader) ReadSint64() (int64, error) {
	value, err := r.ReadVarint()
	if err != nil {
		return 0, err
	}
	return int64(value>>1) ^ -int64(value&1), nil
}

// ReadFixed32 reads four bytes.
func (r *Reader) ReadFixed32() (uint32, error) {
	if r.pos+4 > len(r.buf) {
		return 0, ErrUnexpectedEnd
	}
	value := binary.LittleEndian.Uint32(r.buf[r.pos:])
	r.pos += 4
	return value, nil
}

// ReadFixed64 reads eight bytes.
func (r *Reader) ReadFixed64() (uint64, error) {
	if r.pos+8 > len(r.buf) {
		return 0, ErrUnexpectedEnd
	}
	value := binary.LittleEndian.Uint64(r.buf[r.pos:])
	r.pos += 8
	return value, nil
}

// ReadFloat reads a number of 32 bits.
func (r *Reader) ReadFloat() (float32, error) {
	value, err := r.ReadFixed32()
	if err != nil {
		return 0, err
	}
	return math.Float32frombits(value), nil
}

// ReadDouble reads a number of 64 bits.
func (r *Reader) ReadDouble() (float64, error) {
	value, err := r.ReadFixed64()
	if err != nil {
		return 0, err
	}
	return math.Float64frombits(value), nil
}

// Skip skips a value of the type [typ].
func (r *Reader) Skip(typ int) error {
	switch typ {
	case TypeVarint:
		_, err := r.ReadVarint()
		return err
	case TypeFixed64:
		if r.pos+8 > len(r.buf) {
			return ErrUnexpectedEnd
		}
		r.pos += 8
		return nil
	case TypeBytes:
		_, err := r.ReadBytes()
		return err
	case TypeFixed32:
		if r.pos+4 > len(r.buf) {
			return ErrUnexpectedEnd
		}
		r.pos += 4
		return nil
	default:
		return fmt.Errorf("wire: the wire type %d is not known", typ)
	}
}

// ReadRawVarint reads a number that is written without a tag.
//
// The answer of a method that answers with an enum is the number of the enum
// and nothing else.
func ReadRawVarint(data []byte) (int64, error) {
	reader := NewReader(data)
	value, err := reader.ReadVarint()
	if err != nil {
		return 0, err
	}
	return int64(value), nil
}

// UnpackBool reads the values of a packed field of booleans.
func UnpackBool(data []byte) ([]bool, error) {
	reader := NewReader(data)
	var values []bool
	for !reader.Done() {
		value, err := reader.ReadBool()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackInt32 reads the values of a packed field of signed numbers of 32 bits.
func UnpackInt32(data []byte) ([]int32, error) {
	reader := NewReader(data)
	var values []int32
	for !reader.Done() {
		value, err := reader.ReadInt32()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackInt64 reads the values of a packed field of signed numbers of 64 bits.
func UnpackInt64(data []byte) ([]int64, error) {
	reader := NewReader(data)
	var values []int64
	for !reader.Done() {
		value, err := reader.ReadInt64()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackUint32 reads the values of a packed field of numbers of 32 bits.
func UnpackUint32(data []byte) ([]uint32, error) {
	reader := NewReader(data)
	var values []uint32
	for !reader.Done() {
		value, err := reader.ReadUint32()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackUint64 reads the values of a packed field of numbers of 64 bits.
func UnpackUint64(data []byte) ([]uint64, error) {
	reader := NewReader(data)
	var values []uint64
	for !reader.Done() {
		value, err := reader.ReadUint64()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackSint32 reads the values of a packed field of signed numbers of 32 bits.
func UnpackSint32(data []byte) ([]int32, error) {
	reader := NewReader(data)
	var values []int32
	for !reader.Done() {
		value, err := reader.ReadSint32()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackSint64 reads the values of a packed field of signed numbers of 64 bits.
func UnpackSint64(data []byte) ([]int64, error) {
	reader := NewReader(data)
	var values []int64
	for !reader.Done() {
		value, err := reader.ReadSint64()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackFixed32 reads the values of a packed field of numbers of 32 bits.
func UnpackFixed32(data []byte) ([]uint32, error) {
	reader := NewReader(data)
	var values []uint32
	for !reader.Done() {
		value, err := reader.ReadFixed32()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackFixed64 reads the values of a packed field of numbers of 64 bits.
func UnpackFixed64(data []byte) ([]uint64, error) {
	reader := NewReader(data)
	var values []uint64
	for !reader.Done() {
		value, err := reader.ReadFixed64()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackFloat reads the values of a packed field of numbers of 32 bits.
func UnpackFloat(data []byte) ([]float32, error) {
	reader := NewReader(data)
	var values []float32
	for !reader.Done() {
		value, err := reader.ReadFloat()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}

// UnpackDouble reads the values of a packed field of numbers of 64 bits.
func UnpackDouble(data []byte) ([]float64, error) {
	reader := NewReader(data)
	var values []float64
	for !reader.Done() {
		value, err := reader.ReadDouble()
		if err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, nil
}
''';

/// The source of the transport that talks to a gRPC server.
const String goGrpcSource =
    r'''// Package grpc talks to a gRPC server over HTTP/2.
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
''';
