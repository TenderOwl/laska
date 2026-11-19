package wire

import (
	"bytes"
	"testing"
)

func TestTheWriterWritesTheFieldsOfAMessage(t *testing.T) {
	w := NewWriter()
	w.WriteString(1, "hello")
	w.WriteInt32(2, 42)
	w.WriteBool(3, true)

	want := []byte{
		0x0a, 0x05, 'h', 'e', 'l', 'l', 'o',
		0x10, 0x2a,
		0x18, 0x01,
	}
	if !bytes.Equal(w.Bytes(), want) {
		t.Fatalf("the bytes of the message are %x, want %x", w.Bytes(), want)
	}
}

func TestTheWriterWritesANegativeNumber(t *testing.T) {
	w := NewWriter()
	w.WriteInt32(1, -1)

	// A negative number takes ten bytes, the way protobuf writes it.
	want := []byte{0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01}
	if !bytes.Equal(w.Bytes(), want) {
		t.Fatalf("the bytes of the message are %x, want %x", w.Bytes(), want)
	}
}

func TestTheWriterWritesAZigzagNumber(t *testing.T) {
	w := NewWriter()
	w.WriteSint32(1, -1)
	w.WriteSint64(2, 1)

	want := []byte{0x08, 0x01, 0x10, 0x02}
	if !bytes.Equal(w.Bytes(), want) {
		t.Fatalf("the bytes of the message are %x, want %x", w.Bytes(), want)
	}
}

func TestTheWriterWritesTheValuesOfAPackedField(t *testing.T) {
	w := NewWriter()
	packed := NewWriter()
	packed.WriteRawVarint(1)
	packed.WriteRawVarint(300)
	w.WriteBytes(1, packed.Bytes())

	want := []byte{0x0a, 0x03, 0x01, 0xac, 0x02}
	if !bytes.Equal(w.Bytes(), want) {
		t.Fatalf("the bytes of the message are %x, want %x", w.Bytes(), want)
	}
}

func TestTheReaderReadsTheFieldsOfAMessage(t *testing.T) {
	data := []byte{
		0x0a, 0x05, 'h', 'e', 'l', 'l', 'o',
		0x10, 0x2a,
		0x18, 0x01,
	}

	r := NewReader(data)

	field, typ, err := r.Next()
	if err != nil || field != 1 || typ != TypeBytes {
		t.Fatalf("the first field is %d of the type %d, want 1 of the type %d", field, typ, TypeBytes)
	}
	text, err := r.ReadString()
	if err != nil || text != "hello" {
		t.Fatalf("the value of the first field is %q, want %q", text, "hello")
	}

	field, typ, err = r.Next()
	if err != nil || field != 2 || typ != TypeVarint {
		t.Fatalf("the second field is %d of the type %d, want 2 of the type %d", field, typ, TypeVarint)
	}
	number, err := r.ReadInt32()
	if err != nil || number != 42 {
		t.Fatalf("the value of the second field is %d, want 42", number)
	}

	field, typ, err = r.Next()
	if err != nil || field != 3 || typ != TypeVarint {
		t.Fatalf("the third field is %d of the type %d, want 3 of the type %d", field, typ, TypeVarint)
	}
	flag, err := r.ReadBool()
	if err != nil || !flag {
		t.Fatalf("the value of the third field is %t, want true", flag)
	}

	if _, _, err = r.Next(); err == nil {
		t.Fatal("the reader is over the message")
	}
}

func TestTheReaderSkipsAFieldItDoesNotKnow(t *testing.T) {
	data := []byte{
		0x0a, 0x05, 'h', 'e', 'l', 'l', 'o',
		0x10, 0x2a,
	}

	r := NewReader(data)

	field, _, err := r.Next()
	if err != nil || field != 1 {
		t.Fatalf("the first field is %d, want 1", field)
	}
	if _, err := r.ReadString(); err != nil {
		t.Fatalf("the value of the first field is not read: %v", err)
	}

	field, typ, err := r.Next()
	if err != nil || field != 2 || typ != TypeVarint {
		t.Fatalf("the second field is %d of the type %d, want 2 of the type %d", field, typ, TypeVarint)
	}
	if err := r.Skip(typ); err != nil {
		t.Fatalf("the second field is not skipped: %v", err)
	}
	if !r.Done() {
		t.Fatal("the reader is not over the message")
	}
}

func TestTheReaderReadsTheValuesOfAPackedField(t *testing.T) {
	data := []byte{0x0a, 0x03, 0x01, 0xac, 0x02}

	r := NewReader(data)

	_, typ, err := r.Next()
	if err != nil || typ != TypeBytes {
		t.Fatalf("the field is of the type %d, want %d", typ, TypeBytes)
	}
	packed, err := r.ReadBytes()
	if err != nil {
		t.Fatalf("the values of the field are not read: %v", err)
	}

	values, err := UnpackUint32(packed)
	if err != nil {
		t.Fatalf("the values of the field are not unpacked: %v", err)
	}
	if len(values) != 2 || values[0] != 1 || values[1] != 300 {
		t.Fatalf("the values of the field are %v, want [1 300]", values)
	}
}

func TestTheReaderReadsANegativeNumber(t *testing.T) {
	data := []byte{0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01}

	r := NewReader(data)

	if _, _, err := r.Next(); err != nil {
		t.Fatalf("the field is not read: %v", err)
	}
	number, err := r.ReadInt32()
	if err != nil || number != -1 {
		t.Fatalf("the value of the field is %d, want -1", number)
	}
}

func TestTheReaderReadsANumberWithoutATag(t *testing.T) {
	number, err := ReadRawVarint([]byte{0x2a})
	if err != nil || number != 42 {
		t.Fatalf("the number is %d, want 42", number)
	}
}

func TestTheReaderFailsOnAMessageThatEndsInTheMiddleOfAValue(t *testing.T) {
	r := NewReader([]byte{0x0a, 0x05, 'h'})

	if _, _, err := r.Next(); err != nil {
		t.Fatalf("the field is not read: %v", err)
	}
	if _, err := r.ReadBytes(); err == nil {
		t.Fatal("the value of the field is read out of a message that is cut short")
	}
}
