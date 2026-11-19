package users

import (
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

// The tests of the client talk to a server that speaks gRPC over HTTP/2
// without encryption, the way a service of a cluster is reached.

// frame wraps the bytes of a message in the frame of gRPC.
func frame(payload []byte) []byte {
	out := make([]byte, 5+len(payload))
	binary.BigEndian.PutUint32(out[1:5], uint32(len(payload)))
	copy(out[5:], payload)
	return out
}

// startServer starts a server that answers the calls of the test and returns
// the address it listens to.
func startServer(t *testing.T, handler http.HandlerFunc) string {
	t.Helper()

	protocols := new(http.Protocols)
	protocols.SetUnencryptedHTTP2(true)

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("the server does not listen: %v", err)
	}

	server := &http.Server{Handler: handler, Protocols: protocols}
	go func() {
		_ = server.Serve(listener)
	}()
	t.Cleanup(func() {
		_ = server.Close()
	})

	return listener.Addr().String()
}

// The handler of the server of the tests.
//
// It answers the call of the GetUser method with a user, and every other call
// with a failure.
func handler(t *testing.T) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/grpc+proto")

		if r.URL.Path != "/users.v1.UsersService/GetUser" {
			w.Header().Set("Grpc-Status", "12")
			w.Header().Set("Grpc-Message", "the method is not known")
			w.WriteHeader(http.StatusOK)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Errorf("the request of the call is not read: %v", err)
			w.Header().Set("Grpc-Status", "13")
			w.WriteHeader(http.StatusOK)
			return
		}
		if len(body) < 5 {
			t.Errorf("the request of the call is %d bytes long, want at least 5", len(body))
			w.Header().Set("Grpc-Status", "13")
			w.WriteHeader(http.StatusOK)
			return
		}

		request := &GetUserRequest{}
		if err := request.UnmarshalProto(body[5:]); err != nil {
			t.Errorf("the request of the call is not read: %v", err)
			w.Header().Set("Grpc-Status", "13")
			w.WriteHeader(http.StatusOK)
			return
		}

		answer := &User{
			Id:    request.Id,
			Email: "user@example.com",
			Role:  UserRoleAdmin,
		}

		w.Header().Set("Trailer", "Grpc-Status")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(frame(answer.MarshalProto()))
		w.Header().Set("Grpc-Status", "0")
	}
}

func TestTheClientCallsTheService(t *testing.T) {
	address := startServer(t, handler(t))

	client, err := NewUsersServiceClient(address, CallOptions{Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("the client does not open the connection: %v", err)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	user, err := client.GetUser(ctx, &GetUserRequest{Id: "u_1"})
	if err != nil {
		t.Fatalf("the call of the service fails: %v", err)
	}

	if user.Id != "u_1" {
		t.Fatalf("the identifier of the user is %q, want %q", user.Id, "u_1")
	}
	if user.Email != "user@example.com" {
		t.Fatalf("the email of the user is %q, want %q", user.Email, "user@example.com")
	}
	if user.Role != UserRoleAdmin {
		t.Fatalf("the role of the user is %v, want it to be the admin one", user.Role)
	}
}

func TestTheClientReportsTheFailureOfACall(t *testing.T) {
	address := startServer(t, handler(t))

	client, err := NewUsersServiceClient(address, CallOptions{Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("the client does not open the connection: %v", err)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err = client.ListUsers(ctx, &ListUsersRequest{Limit: 10})
	if err == nil {
		t.Fatal("the call of the method that is not known succeeds")
	}

	var status *StatusError
	if !errors.As(err, &status) {
		t.Fatalf("the failure of the call is %q, want it to be a status", err)
	}
	if status.Code != 12 {
		t.Fatalf("the status of the failure is %d, want 12", status.Code)
	}
	if !strings.Contains(status.Message, "not known") {
		t.Fatalf("the message of the failure is %q, want it to hold the reason", status.Message)
	}
}

func TestTheClientSendsTheMetadataOfTheCall(t *testing.T) {
	var seen string
	address := startServer(t, func(w http.ResponseWriter, r *http.Request) {
		seen = r.Header.Get("Authorization")

		w.Header().Set("Content-Type", "application/grpc+proto")
		w.Header().Set("Trailer", "Grpc-Status")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(frame((&User{Id: "u_1"}).MarshalProto()))
		w.Header().Set("Grpc-Status", "0")
	})

	client, err := NewUsersServiceClient(address, CallOptions{Timeout: 5 * time.Second})
	if err != nil {
		t.Fatalf("the client does not open the connection: %v", err)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err = client.GetUser(ctx, &GetUserRequest{Id: "u_1"}, CallOptions{
		Timeout:  5 * time.Second,
		Metadata: map[string]string{"Authorization": "Bearer token"},
	})
	if err != nil {
		t.Fatalf("the call of the service fails: %v", err)
	}

	if seen != "Bearer token" {
		t.Fatalf("the metadata of the call is %q, want %q", seen, "Bearer token")
	}
}
