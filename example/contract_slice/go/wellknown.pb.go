// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Regenerate with: laska contract sdk --lang=go

package users

import (
	"io"

	"github.com/TenderOwl/laska/example/contract_slice/go/internal/wire"
)

// ProtoTimestamp is the time of the protocol buffers.
type ProtoTimestamp struct {
	// Seconds is the number of the seconds.
	Seconds int64
	// Nanos is the number of the nanoseconds.
	Nanos int32
}

// MarshalProto writes the message on the wire.
func (m *ProtoTimestamp) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Seconds != 0 {
		w.WriteInt64(1, m.Seconds)
	}
	if m.Nanos != 0 {
		w.WriteInt32(2, m.Nanos)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ProtoTimestamp) UnmarshalProto(data []byte) error {
	*m = ProtoTimestamp{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt64()
			if err != nil {
				return err
			}
			m.Seconds = value
		case 2:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt32()
			if err != nil {
				return err
			}
			m.Nanos = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// ProtoDuration is the duration of the protocol buffers.
type ProtoDuration struct {
	// Seconds is the number of the seconds.
	Seconds int64
	// Nanos is the number of the nanoseconds.
	Nanos int32
}

// MarshalProto writes the message on the wire.
func (m *ProtoDuration) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.Seconds != 0 {
		w.WriteInt64(1, m.Seconds)
	}
	if m.Nanos != 0 {
		w.WriteInt32(2, m.Nanos)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ProtoDuration) UnmarshalProto(data []byte) error {
	*m = ProtoDuration{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt64()
			if err != nil {
				return err
			}
			m.Seconds = value
		case 2:
			if typ != wire.TypeVarint {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadInt32()
			if err != nil {
				return err
			}
			m.Nanos = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// ProtoAny is a message of an unknown type of the protocol buffers.
type ProtoAny struct {
	// TypeUrl is the address of the type.
	TypeUrl string
	// Value holds the bytes of the message.
	Value []byte
}

// MarshalProto writes the message on the wire.
func (m *ProtoAny) MarshalProto() []byte {
	w := wire.NewWriter()
	if m.TypeUrl != "" {
		w.WriteString(1, m.TypeUrl)
	}
	if len(m.Value) > 0 {
		w.WriteBytes(2, m.Value)
	}
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ProtoAny) UnmarshalProto(data []byte) error {
	*m = ProtoAny{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		case 1:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadString()
			if err != nil {
				return err
			}
			m.TypeUrl = value
		case 2:
			if typ != wire.TypeBytes {
				if err := r.Skip(typ); err != nil {
					return err
				}
				continue
			}
			value, err := r.ReadBytes()
			if err != nil {
				return err
			}
			m.Value = value
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}

// ProtoEmpty is the empty message of the protocol buffers.
type ProtoEmpty struct {
}

// MarshalProto writes the message on the wire.
func (m *ProtoEmpty) MarshalProto() []byte {
	w := wire.NewWriter()
	return w.Bytes()
}

// UnmarshalProto reads the message out of its bytes.
func (m *ProtoEmpty) UnmarshalProto(data []byte) error {
	*m = ProtoEmpty{}
	r := wire.NewReader(data)
	for {
		field, typ, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		switch field {
		default:
			if err := r.Skip(typ); err != nil {
				return err
			}
		}
	}
	return nil
}
